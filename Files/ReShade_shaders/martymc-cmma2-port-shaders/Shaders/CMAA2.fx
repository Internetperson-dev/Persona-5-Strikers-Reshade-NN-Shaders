/*=============================================================================

	ReShade 4 effect file
    github.com/martymcmodding

    Rough port of CMAA2 to ReShade by Pascal Gilcher
    I do not claim any copyright to any of the work used in this product

    CMAA2 (Copyright (c) 2018, Intel Corporation) is licensed under
    http://www.apache.org/licenses/LICENSE-2.0

    Details of implementation:

    ReShade is missing most of the features CMAA2 uses for acceleration. 
    Results are lowered performance and write race conditions, manifesting 
    as flickering.
    A workaround for the second problem is randomizing the writes to 
    multiple different buffers and blending these at the end. 
    This only lowers the probability of collisions and does not solve them. 
    Using some napkin math, I decided that 4 buffers is sufficient.

    I removed those features that will never be used on ReShade
    but left the rest of the code as vanilla as possible 
    to facilitate later implementation of missing features, 
    should ReShade gain functionality. 
    
    CMAA2_COLLECT_EXPAND_BLEND_ITEMS is removed entirely.

    As mentioned above, I do not claim any copyright to any of the present
    source code in this file, feel free to modify, add and build on top
    of the components I introduced.

=============================================================================*/


#define WRITE_COLLISION_REVOLVER           1        //enable randomized writing of buffers
#define USE_FP16                           0        //on RTX 3080, fp16 is slower than fp32, so disabled by default. Default for official CMAA2 as well

//CMAA2 tweaks that make sense to modify for user
#define CMAA2_EDGE_DETECTION_LUMA_PATH     0        //0: full color 1: log luma in place (2 disabled as it's using luma from outside)
#define CMAA2_EXTRA_SHARPNESS              0

/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform float g_CMAA2_EdgeThreshold <
    ui_type = "drag";
    ui_min = 0.02;
    ui_max = 0.15;
> = 0.1;

/*=============================================================================
	Textures, Samplers, Globals, Preprocessor settings
=============================================================================*/

//wrapping these rather than substituting - makes implementing missing features easier down the line if code is vanilla
#if USE_FP16 == 1
 #define lpfloat                                     min16float
 #define lpfloat2                                    min16float2 
 #define lpfloat3                                    min16float3 
 #define lpfloat4                                    min16float4
#else 
 #define lpfloat                                     float
 #define lpfloat2                                    float2 
 #define lpfloat3                                    float3 
 #define lpfloat4                                    float4
#endif

#define GroupMemoryBarrierWithGroupSync             barrier
#define CMAA2_CS_INPUT_KERNEL_SIZE_X                16
#define CMAA2_CS_INPUT_KERNEL_SIZE_Y                16
#define CMAA2_CS_OUTPUT_KERNEL_SIZE_X               (CMAA2_CS_INPUT_KERNEL_SIZE_X-2)
#define CMAA2_CS_OUTPUT_KERNEL_SIZE_Y               (CMAA2_CS_INPUT_KERNEL_SIZE_Y-2)

//from my tests, it's slower on ReShade?
#define CMAA_PACK_SINGLE_SAMPLE_EDGE_TO_HALF_WIDTH  0 // adds more ALU but reduces memory use for edges by half by packing two 4 bit edge info into one R8_UINT texel - helps on all HW except at really low res

#if CMAA2_EXTRA_SHARPNESS
 #define g_CMAA2_LocalContrastAdaptationAmount       lpfloat(0.15)
 #define g_CMAA2_SimpleShapeBlurinessAmount          lpfloat(0.07)
#else
 #define g_CMAA2_LocalContrastAdaptationAmount       lpfloat(0.10)
 #define g_CMAA2_SimpleShapeBlurinessAmount          lpfloat(0.10)
#endif

// these are blendZ settings, determined empirically :)
static const lpfloat c_symmetryCorrectionOffset = lpfloat( 0.22 );
#if CMAA2_EXTRA_SHARPNESS
static const lpfloat c_dampeningEffect          = lpfloat( 0.11 );
#else
static const lpfloat c_dampeningEffect          = lpfloat( 0.15 );
#endif

//integer divide, rounding up
#define CEIL_DIV(num, denom) (((num - 1) / denom) + 1)

#if CMAA_PACK_SINGLE_SAMPLE_EDGE_TO_HALF_WIDTH != 0
texture g_workingEdges { Width = CEIL_DIV(BUFFER_WIDTH, 2); Height = BUFFER_HEIGHT; Format = R8; };
#else 
texture g_workingEdges { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
#endif

sampler s_workingEdges { Texture = g_workingEdges;	MinFilter=POINT;MipFilter=POINT;MagFilter=POINT; };
storage st_workingEdges { Texture = g_workingEdges; };

#if WRITE_COLLISION_REVOLVER != 0
texture g_workingDeferredBlendItems0 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler s_workingDeferredBlendItems0 { Texture = g_workingDeferredBlendItems0;	MinFilter=POINT;MipFilter=POINT;MagFilter=POINT; };
storage st_workingDeferredBlendItems0 { Texture = g_workingDeferredBlendItems0; };
texture g_workingDeferredBlendItems1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler s_workingDeferredBlendItems1 { Texture = g_workingDeferredBlendItems1;	MinFilter=POINT;MipFilter=POINT;MagFilter=POINT; };
storage st_workingDeferredBlendItems1 { Texture = g_workingDeferredBlendItems1; };
texture g_workingDeferredBlendItems2 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler s_workingDeferredBlendItems2 { Texture = g_workingDeferredBlendItems2;	MinFilter=POINT;MipFilter=POINT;MagFilter=POINT; };
storage st_workingDeferredBlendItems2 { Texture = g_workingDeferredBlendItems2; };
texture g_workingDeferredBlendItems3 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler s_workingDeferredBlendItems3 { Texture = g_workingDeferredBlendItems3;	MinFilter=POINT;MipFilter=POINT;MagFilter=POINT; };
storage st_workingDeferredBlendItems3 { Texture = g_workingDeferredBlendItems3; };
#else
texture g_workingDeferredBlendItems { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler s_workingDeferredBlendItems { Texture = g_workingDeferredBlendItems;	MinFilter=POINT;MipFilter=POINT;MagFilter=POINT; };
storage st_workingDeferredBlendItems { Texture = g_workingDeferredBlendItems; };
#endif

texture ColorInputTex : COLOR;
sampler ColorInput 	{ Texture = ColorInputTex; };

struct CSIN 
{
    uint3 groupthreadid     : SV_GroupThreadID;         //XYZ idx of thread inside group
    uint3 groupid           : SV_GroupID;               //XYZ idx of group inside dispatch
    uint3 dispatchthreadid  : SV_DispatchThreadID;      //XYZ idx of thread inside dispatch
    uint threadid           : SV_GroupIndex;            //flattened idx of thread inside group
};

groupshared lpfloat4 g_groupShared2x2FracEdgesH[CMAA2_CS_INPUT_KERNEL_SIZE_X * CMAA2_CS_INPUT_KERNEL_SIZE_Y];
groupshared lpfloat4 g_groupShared2x2FracEdgesV[CMAA2_CS_INPUT_KERNEL_SIZE_X * CMAA2_CS_INPUT_KERNEL_SIZE_Y];

float4 LoadSourceColor(int2 xy, int2 offs, uint msaaidx /*unused*/)
{    
    return tex2Dfetch(ColorInput, xy + offs);
}

void StoreColorSample( uint2 pixelPos, lpfloat3 color, bool isComplexShape, inout uint msaaSampleIndex )
{
    /*uint counterIndex;  g_workingControlBuffer.InterlockedAdd( 4*12, 1, counterIndex );

    // quad coordinates
    uint2 quadPos       = pixelPos / uint2( 2, 2 );
    // 2x2 inter-quad coordinates
    uint offsetXY       = (pixelPos.y % 2) * 2 + (pixelPos.x % 2);
    // encode item-specific info: {2 bits for 2x2 quad location}, {3 bits for MSAA sample index}, {1 bit for isComplexShape flag}, {26 bits left for address (index)}
    uint header         = ( offsetXY << 30 ) | ( msaaSampleIndex << 27 ) | ( isComplexShape << 26 );

    uint counterIndexWithHeader = counterIndex | header;

    uint originalIndex;
    InterlockedExchange( g_workingDeferredBlendItemListHeads[ quadPos ], counterIndexWithHeader, originalIndex );
    g_workingDeferredBlendItemList[counterIndex] = uint2( originalIndex, InternalPackColor( color ) );

    // First one added?
    if( originalIndex == 0xFFFFFFFF )
    {
        // Make a list of all edge pixels - these cover all potential pixels where AA is applied.
        uint edgeListCounter;  g_workingControlBuffer.InterlockedAdd( 4*8, 1, edgeListCounter );
        g_workingDeferredBlendLocationList[edgeListCounter] = (quadPos.x << 16) | quadPos.y;
    }*/

#if WRITE_COLLISION_REVOLVER != 0    
    if(isComplexShape)
    {
        msaaSampleIndex++;
        uint modidx = msaaSampleIndex & 0x3;
        if(modidx == 0) tex2Dstore(st_workingDeferredBlendItems0, pixelPos, float4(color, 1));
        else if(modidx == 1) tex2Dstore(st_workingDeferredBlendItems1, pixelPos, float4(color, 1));
        else if(modidx == 2) tex2Dstore(st_workingDeferredBlendItems2, pixelPos, float4(color, 1));
        else if(modidx == 3) tex2Dstore(st_workingDeferredBlendItems3, pixelPos, float4(color, 1));
    }
    else 
    {
        tex2Dstore(st_workingDeferredBlendItems0, pixelPos, float4(color, 0));
        tex2Dstore(st_workingDeferredBlendItems1, pixelPos, float4(color, 0));
        tex2Dstore(st_workingDeferredBlendItems2, pixelPos, float4(color, 0));
        tex2Dstore(st_workingDeferredBlendItems3, pixelPos, float4(color, 0));
    }
#else
    tex2Dstore(st_workingDeferredBlendItems, pixelPos, float4(color, isComplexShape));
#endif
}

uint LoadEdge( int2 pixelPos, int2 offset, uint msaaSampleIndex )
{
#if CMAA_PACK_SINGLE_SAMPLE_EDGE_TO_HALF_WIDTH
    uint a      = uint(pixelPos.x+offset.x) % 2;
    uint edge   = tex2Dfetch(s_workingEdges, uint2( uint(pixelPos.x+offset.x)/2, pixelPos.y + offset.y ) ).x * 255 + 0.5;   //(uint)(g_workingEdges.Load( uint2( uint(pixelPos.x+offset.x)/2, pixelPos.y + offset.y ) ).x * 255.0 + 0.5);
    edge = (edge >> (a*4)) & 0xF;
#else
    uint edge   = tex2Dfetch(s_workingEdges, pixelPos + offset).x * 255 + 0.5; //g_workingEdges.Load( pixelPos + offset ).x; //mcfly extension, if CMAA_PACK_SINGLE_SAMPLE_EDGE_TO_HALF_WIDTH incompatible to EDGE_UNORM by default
#endif
    return edge;
}

float3 ProcessColorForEdgeDetect( float3 color )
{
    //pixelColors[i] = LINEAR_to_SRGB( pixelColors[i] );            // correct reference
    //pixelColors[i] = pow( max( 0, pixelColors[i], 1.0 / 2.4 ) );  // approximate sRGB curve
    return sqrt( color ); // just very roughly approximate RGB curve
}

float EdgeDetectColorCalcDiff( float3 colorA, float3 colorB )
{
    const float3 LumWeights = float3( 0.299, 0.587, 0.114 );
    float3 diff = abs( (colorA.rgb - colorB.rgb) );
    return dot( diff.rgb, LumWeights.rgb );
}

float RGBToLumaForEdges( float3 linearRGB )
{
    
#if 0
    // this matches Miniengine luma path
    float Luma = dot( linearRGB, float3(0.212671, 0.715160, 0.072169) );
    return log2(1 + Luma * 15) / 4;
#else
    // this is what original FXAA (and consequently CMAA2) use by default - these coefficients correspond to Rec. 601 and those should be
    // used on gamma-compressed components (see https://en.wikipedia.org/wiki/Luma_(video)#Rec._601_luma_versus_Rec._709_luma_coefficients), 
    float luma = dot( sqrt( linearRGB.rgb ), float3( 0.299, 0.587, 0.114 ) );  // http://en.wikipedia.org/wiki/CCIR_601
    // using sqrt luma for now but log luma like in miniengine provides a nicer curve on the low-end
    return luma;
#endif    
    //return dot(linearRGB, float3(0.212671, 0.715160, 0.072169)); //already operating in sRGB space
}

void GroupsharedLoadQuadHV( uint addr, out lpfloat2 e00, out lpfloat2 e10, out lpfloat2 e01, out lpfloat2 e11 ) 
{ 
    lpfloat4 valH = g_groupShared2x2FracEdgesH[addr]; e00.y = valH.x; e10.y = valH.y; e01.y = valH.z; e11.y = valH.w; 
    lpfloat4 valV = g_groupShared2x2FracEdgesV[addr]; e00.x = valV.x; e10.x = valV.y; e01.x = valV.z; e11.x = valV.w; 
}

#define ComputeLocalContrastV(x, y, neighbourhood) max( max( neighbourhood[((x) + 1) * 4 + ((y) + 0)].g, neighbourhood[((x) + 1) * 4 + ((y) + 1)].g ), max( neighbourhood[((x) + 2) * 4 + ((y) + 0)].g, neighbourhood[((x) + 2) * 4 + ((y) + 1)].g ) ) * lpfloat( g_CMAA2_LocalContrastAdaptationAmount )
#define ComputeLocalContrastH(x, y, neighbourhood) max( max( neighbourhood[((x) + 0) * 4 + ((y) + 1)].r, neighbourhood[((x) + 1) * 4 + ((y) + 1)].r ), max( neighbourhood[((x) + 0) * 4 + ((y) + 2)].r, neighbourhood[((x) + 1) * 4 + ((y) + 2)].r ) ) * lpfloat( g_CMAA2_LocalContrastAdaptationAmount )

lpfloat GetActualEdgeThreshold( )
{
    lpfloat retVal = g_CMAA2_EdgeThreshold;
    return retVal;
}

uint PackEdges( lpfloat4 edges )   // input edges are binary 0 or 1
{
    return (uint)dot( edges, lpfloat4( 1, 2, 4, 8 ) );
}
uint4 UnpackEdges( uint value )
{
    int4 ret;
    ret.x = ( value & 0x01 ) != 0;
    ret.y = ( value & 0x02 ) != 0;
    ret.z = ( value & 0x04 ) != 0;
    ret.w = ( value & 0x08 ) != 0;
    return ret;
}
lpfloat4 UnpackEdgesFlt( uint value )
{
    lpfloat4 ret;
    ret.x = ( value & 0x01 ) != 0;
    ret.y = ( value & 0x02 ) != 0;
    ret.z = ( value & 0x04 ) != 0;
    ret.w = ( value & 0x08 ) != 0;
    return ret;
}

void CS_EdgeDetect(in CSIN IN)
{
    // screen position in the input (expanded) kernel (shifted one 2x2 block up/left)
    uint2 pixelPos = IN.groupid.xy * int2( CMAA2_CS_OUTPUT_KERNEL_SIZE_X, CMAA2_CS_OUTPUT_KERNEL_SIZE_Y ) + IN.groupthreadid.xy - int2( 1, 1 );
    pixelPos *= int2( 2, 2 );

    const uint2 qeOffsets[4]        = { uint2(0, 0), uint2(1, 0), uint2(0, 1), uint2(1, 1) };
    const uint rowStride2x2         = CMAA2_CS_INPUT_KERNEL_SIZE_X;
    const uint centerAddr2x2        = IN.groupthreadid.x + IN.groupthreadid.y * rowStride2x2;
    const bool inOutputKernel       = !any( bool4( IN.groupthreadid.x == ( CMAA2_CS_INPUT_KERNEL_SIZE_X - 1 ), IN.groupthreadid.x == 0, IN.groupthreadid.y == ( CMAA2_CS_INPUT_KERNEL_SIZE_Y - 1 ), IN.groupthreadid.y == 0 ) );

    uint i;
   // lpfloat2 qe0, qe1, qe2, qe3; //see below

    lpfloat2 qe[4];

    uint4 outEdges = 0;

    uint msaaSampleIndex = 0;

    // edge detection
#if CMAA2_EDGE_DETECTION_LUMA_PATH == 0
    lpfloat3 pixelColors[3 * 3 - 1];
    [unroll]
    for( i = 0; i < 3 * 3 - 1; i++ )
        pixelColors[i] = LoadSourceColor( pixelPos, int2( i % 3, i / 3 ), msaaSampleIndex ).rgb;

    [unroll]
    for( i = 0; i < 3 * 3 - 1; i++ )
        pixelColors[i] = ProcessColorForEdgeDetect( pixelColors[i] );

    //wrapping ComputeEdge()
    for(i = 0; i < 4; i++)
    {
        int x = qeOffsets[i].x;
        int y = qeOffsets[i].y;
        qe[i].x = EdgeDetectColorCalcDiff( pixelColors[x + y * 3].rgb, pixelColors[x + 1 + y * 3].rgb );
        qe[i].y = EdgeDetectColorCalcDiff( pixelColors[x + y * 3].rgb, pixelColors[x + ( y + 1 ) * 3].rgb );
    }
#else // CMAA2_EDGE_DETECTION_LUMA_PATH != 0
    lpfloat pixelLumas[3 * 3 - 1];
    //#if CMAA2_EDGE_DETECTION_LUMA_PATH == 1 // compute in-place
    [unroll]
    for( i = 0; i < 3 * 3 - 1; i++ )
    {
        lpfloat3 color = LoadSourceColor( pixelPos, int2( i % 3, i / 3 ), msaaSampleIndex ).rgb;
        pixelLumas[i] = RGBToLumaForEdges( color );
    }
    //#endif

    //wrapping ComputeEdgeLuma()
    for(i = 0; i < 4; i++)
    {
        int x = qeOffsets[i].x;
        int y = qeOffsets[i].y;
        qe[i].x = abs( pixelLumas[x + y * 3] - pixelLumas[x + 1 + y * 3] );
        qe[i].y = abs( pixelLumas[x + y * 3] - pixelLumas[x + ( y + 1 ) * 3] );
    }
#endif
    //repacking so it's easier lateron
    lpfloat2 qe0, qe1, qe2, qe3;
    qe0 = qe[0];
    qe1 = qe[1];
    qe2 = qe[2];
    qe3 = qe[3];

    g_groupShared2x2FracEdgesV[centerAddr2x2 + rowStride2x2 * 0] = lpfloat4( qe0.x, qe1.x, qe2.x, qe3.x );
    g_groupShared2x2FracEdgesH[centerAddr2x2 + rowStride2x2 * 0] = lpfloat4( qe0.y, qe1.y, qe2.y, qe3.y );


    GroupMemoryBarrierWithGroupSync( );

    [branch]
    if( inOutputKernel )
    {
        lpfloat2 topRow         = g_groupShared2x2FracEdgesH[ centerAddr2x2 - rowStride2x2 ].zw;   // top row's bottom edge
        lpfloat2 leftColumn     = g_groupShared2x2FracEdgesV[ centerAddr2x2 - 1 ].yw;              // left column's right edge

        bool someNonZeroEdges = any( lpfloat4( qe0, qe1 ) + lpfloat4( qe2, qe3 ) + lpfloat4( topRow[0], topRow[1], leftColumn[0], leftColumn[1] ) );           

        [branch]
        if( someNonZeroEdges )
        {
            // Clear deferred color list heads to empty (if potentially needed - even though some edges might get culled by local contrast adaptation 
            // step below, it's still cheaper to just clear it without additional logic)
            //g_workingDeferredBlendItemListHeads[ uint2( pixelPos ) / 2 ] = 0xFFFFFFFF;//------------------------------------------------------------------------------------------------------------------------------------------------

            lpfloat4 ce[4];

#if 1 // local contrast adaptation
            lpfloat2 dummyd0, dummyd1, dummyd2;
            //lpfloat2 neighbourhood[4][4];
            lpfloat2 neighbourhood[4*4];

            ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            // load & unpack kernel data from SLM
            GroupsharedLoadQuadHV( centerAddr2x2 - rowStride2x2 - 1 , dummyd0, dummyd1, dummyd2, neighbourhood[0*4+0] );
            GroupsharedLoadQuadHV( centerAddr2x2 - rowStride2x2     , dummyd0, dummyd1, neighbourhood[1*4+0], neighbourhood[2*4+0] );
            GroupsharedLoadQuadHV( centerAddr2x2 - rowStride2x2 + 1 , dummyd0, dummyd1, neighbourhood[3*4+0], dummyd2 );
            GroupsharedLoadQuadHV( centerAddr2x2 - 1                , dummyd0, neighbourhood[0*4+1], dummyd1, neighbourhood[0*4+2] );
            GroupsharedLoadQuadHV( centerAddr2x2 + 1                , neighbourhood[3*4+1], dummyd0, neighbourhood[3*4+2], dummyd1 );
            GroupsharedLoadQuadHV( centerAddr2x2 - 1 + rowStride2x2 , dummyd0, neighbourhood[0*4+3], dummyd1, dummyd2 );
            GroupsharedLoadQuadHV( centerAddr2x2 + rowStride2x2     , neighbourhood[1*4+3], neighbourhood[2*4+3], dummyd0, dummyd1 );
            neighbourhood[1*4+0].y = topRow[0]; // already in registers
            neighbourhood[2*4+0].y = topRow[1]; // already in registers
            neighbourhood[0*4+1].x = leftColumn[0]; // already in registers
            neighbourhood[0*4+2].x = leftColumn[1]; // already in registers
            neighbourhood[1*4+1] = qe0; // already in registers
            neighbourhood[2*4+1] = qe1; // already in registers
            neighbourhood[1*4+2] = qe2; // already in registers
            neighbourhood[2*4+2] = qe3; // already in registers
                ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        
            topRow[0]     = ( topRow[0]     - ComputeLocalContrastH( 0, -1, neighbourhood ) ) > GetActualEdgeThreshold();
            topRow[1]     = ( topRow[1]     - ComputeLocalContrastH( 1, -1, neighbourhood ) ) > GetActualEdgeThreshold();
            leftColumn[0] = ( leftColumn[0] - ComputeLocalContrastV( -1, 0, neighbourhood ) ) > GetActualEdgeThreshold();
            leftColumn[1] = ( leftColumn[1] - ComputeLocalContrastV( -1, 1, neighbourhood ) ) > GetActualEdgeThreshold();

            ce[0].x = ( qe0.x - ComputeLocalContrastV( 0, 0, neighbourhood ) ) > GetActualEdgeThreshold();
            ce[0].y = ( qe0.y - ComputeLocalContrastH( 0, 0, neighbourhood ) ) > GetActualEdgeThreshold();
            ce[1].x = ( qe1.x - ComputeLocalContrastV( 1, 0, neighbourhood ) ) > GetActualEdgeThreshold();
            ce[1].y = ( qe1.y - ComputeLocalContrastH( 1, 0, neighbourhood ) ) > GetActualEdgeThreshold();
            ce[2].x = ( qe2.x - ComputeLocalContrastV( 0, 1, neighbourhood ) ) > GetActualEdgeThreshold();
            ce[2].y = ( qe2.y - ComputeLocalContrastH( 0, 1, neighbourhood ) ) > GetActualEdgeThreshold();
            ce[3].x = ( qe3.x - ComputeLocalContrastV( 1, 1, neighbourhood ) ) > GetActualEdgeThreshold();
            ce[3].y = ( qe3.y - ComputeLocalContrastH( 1, 1, neighbourhood ) ) > GetActualEdgeThreshold();
#else
            topRow[0]     = topRow[0]    > GetActualEdgeThreshold();
            topRow[1]     = topRow[1]    > GetActualEdgeThreshold();
            leftColumn[0] = leftColumn[0]> GetActualEdgeThreshold();
            leftColumn[1] = leftColumn[1]> GetActualEdgeThreshold();
            ce[0].x = qe0.x > GetActualEdgeThreshold();
            ce[0].y = qe0.y > GetActualEdgeThreshold();
            ce[1].x = qe1.x > GetActualEdgeThreshold();
            ce[1].y = qe1.y > GetActualEdgeThreshold();
            ce[2].x = qe2.x > GetActualEdgeThreshold();
            ce[2].y = qe2.y > GetActualEdgeThreshold();
            ce[3].x = qe3.x > GetActualEdgeThreshold();
            ce[3].y = qe3.y > GetActualEdgeThreshold();
 #endif

            //left
            ce[0].z = leftColumn[0];
            ce[1].z = ce[0].x;
            ce[2].z = leftColumn[1];
            ce[3].z = ce[2].x;

            // top
            ce[0].w = topRow[0];
            ce[1].w = topRow[1];
            ce[2].w = ce[0].y;
            ce[3].w = ce[1].y;

            [unroll]
            for( i = 0; i < 4; i++ )
            {
                const uint2 localPixelPos = pixelPos + qeOffsets[i];

                const lpfloat4 edges = ce[i];
                /*
                // if there's at least one two edge corner, this is a candidate for simple or complex shape processing...
                bool isCandidate = ( edges.x * edges.y + edges.y * edges.z + edges.z * edges.w + edges.w * edges.x ) != 0;
                if( isCandidate )
                {
                    uint counterIndex;  g_workingControlBuffer.InterlockedAdd( 4*4, 1, counterIndex );
                    g_workingShapeCandidates[counterIndex] = (localPixelPos.x << 18) | (msaaSampleIndex << 14) | localPixelPos.y;
                }*/

                // Write out edges - we write out all, including empty pixels, to make sure shape detection edge tracing
                // doesn't continue on previous frame's edges that no longer exist.
                uint packedEdge = PackEdges( edges );
                outEdges[i] = packedEdge;
             }
        }
    }

    // finally, write the edges!
    //mcfly: hardcoded to use the unorm path, ReShade limitation
    [branch]
    if( inOutputKernel )
    {
#if CMAA_PACK_SINGLE_SAMPLE_EDGE_TO_HALF_WIDTH
        tex2Dstore(st_workingEdges, int2(pixelPos.x/2, pixelPos.y+0), ((outEdges[1] << 4) | outEdges[0]) / 255.0);
        tex2Dstore(st_workingEdges, int2(pixelPos.x/2, pixelPos.y+1), ((outEdges[3] << 4) | outEdges[2]) / 255.0);
#else
        {
            [unroll] for( uint i = 0; i < 4; i++ )            
            tex2Dstore(st_workingEdges, pixelPos + qeOffsets[i], outEdges[i] / 255.0); //unorm on
        }
#endif
    }
}

lpfloat4 ComputeSimpleShapeBlendValues( lpfloat4 edges, lpfloat4 edgesLeft, lpfloat4 edgesRight, lpfloat4 edgesTop, lpfloat4 edgesBottom, bool dontTestShapeValidity )
{
    // a 3x3 kernel for higher quality handling of L-based shapes (still rather basic and conservative)

    lpfloat fromRight   = edges.r;
    lpfloat fromBelow   = edges.g;
    lpfloat fromLeft    = edges.b;
    lpfloat fromAbove   = edges.a;

    lpfloat blurCoeff = lpfloat( g_CMAA2_SimpleShapeBlurinessAmount );

    lpfloat numberOfEdges = dot( edges, lpfloat4( 1, 1, 1, 1 ) );

    lpfloat numberOfEdgesAllAround = dot(edgesLeft.bga + edgesRight.rga + edgesTop.rba + edgesBottom.rgb, lpfloat3( 1, 1, 1 ) );

    // skip if already tested for before calling this function
    if( !dontTestShapeValidity )
    {
        // No blur for straight edge
        if( numberOfEdges == 1 )
            blurCoeff = 0;

        // L-like step shape ( only blur if it's a corner, not if it's two parallel edges)
        if( numberOfEdges == 2 )
            blurCoeff *= ( ( lpfloat(1.0) - fromBelow * fromAbove ) * ( lpfloat(1.0) - fromRight * fromLeft ) );
    }

    // L-like step shape
    //[branch]
    if( numberOfEdges == 2 )
    {
        blurCoeff *= 0.75;

#if 1
        float k = 0.9f;
#if 0
        fromRight   += k * (edges.g * edgesTop.r +      edges.a * edgesBottom.r );
        fromBelow   += k * (edges.r * edgesLeft.g +     edges.b * edgesRight.g );
        fromLeft    += k * (edges.g * edgesTop.b +      edges.a * edgesBottom.b );
        fromAbove   += k * (edges.b * edgesRight.a +    edges.r * edgesLeft.a );
#else
        fromRight   += k * (edges.g * edgesTop.r     * (1.0-edgesLeft.g)   +     edges.a * edgesBottom.r   * (1.0-edgesLeft.a)      );
        fromBelow   += k * (edges.b * edgesRight.g   * (1.0-edgesTop.b)    +     edges.r * edgesLeft.g     * (1.0-edgesTop.r)       );
        fromLeft    += k * (edges.a * edgesBottom.b  * (1.0-edgesRight.a)  +     edges.g * edgesTop.b      * (1.0-edgesRight.g)     );
        fromAbove   += k * (edges.r * edgesLeft.a    * (1.0-edgesBottom.r) +     edges.b * edgesRight.a   *  (1.0-edgesBottom.b)    );
#endif
#endif
    }

    // if( numberOfEdges == 3 )
    //     blurCoeff *= 0.95;

    // Dampen the blurring effect when lots of neighbouring edges - additionally preserves text and texture detail
#if CMAA2_EXTRA_SHARPNESS
    blurCoeff *= saturate( 1.15 - numberOfEdgesAllAround / 8.0 );
#else
    blurCoeff *= saturate( 1.30 - numberOfEdgesAllAround / 10.0 );
#endif

    return lpfloat4( fromLeft, fromAbove, fromRight, fromBelow ) * blurCoeff;
}

void DetectZsHorizontal( in lpfloat4 edges, in lpfloat4 edgesM1P0, in lpfloat4 edgesP1P0, in lpfloat4 edgesP2P0, out lpfloat invertedZScore, out lpfloat normalZScore )
{
    // Inverted Z case:
    //   __
    //  X|
    // --
    {
        invertedZScore  = edges.r * edges.g *                edgesP1P0.a;
        invertedZScore  *= 2.0 + ((edgesM1P0.g + edgesP2P0.a) ) - (edges.a + edgesP1P0.g) - 0.7 * (edgesP2P0.g + edgesM1P0.a + edges.b + edgesP1P0.r);
    }

    // Normal Z case:
    // __
    //  X|
    //   --
    {
        normalZScore    = edges.r * edges.a *                edgesP1P0.g;
        normalZScore    *= 2.0 + ((edgesM1P0.a + edgesP2P0.g) ) - (edges.g + edgesP1P0.a) - 0.7 * (edgesP2P0.a + edgesM1P0.g + edges.b + edgesP1P0.r);
    }
}

void FindZLineLengths( out lpfloat lineLengthLeft, out lpfloat lineLengthRight, uint2 screenPos, inout bool horizontal, inout bool invertedZShape, const float2 stepRight, uint msaaSampleIndex )
{
// this enables additional conservativeness test but is pretty detrimental to the final effect so left disabled by default even when CMAA2_EXTRA_SHARPNESS is enabled
#define CMAA2_EXTRA_CONSERVATIVENESS2 0
    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    // TODO: a cleaner and faster way to get to these - a precalculated array indexing maybe?
    uint maskLeft, bitsContinueLeft, maskRight, bitsContinueRight;
    {
        // Horizontal (vertical is the same, just rotated 90- counter-clockwise)
        // Inverted Z case:              // Normal Z case:
        //   __                          // __
        //  X|                           //  X|
        // --                            //   --
        uint maskTraceLeft, maskTraceRight;
#if CMAA2_EXTRA_CONSERVATIVENESS2
        uint maskStopLeft, maskStopRight;
#endif
        if( horizontal )
        {
            maskTraceLeft = 0x08; // tracing top edge
            maskTraceRight = 0x02; // tracing bottom edge
#if CMAA2_EXTRA_CONSERVATIVENESS2
            maskStopLeft = 0x01; // stop on right edge
            maskStopRight = 0x04; // stop on left edge
#endif
        }
        else
        {
            maskTraceLeft = 0x04; // tracing left edge
            maskTraceRight = 0x01; // tracing right edge
#if CMAA2_EXTRA_CONSERVATIVENESS2
            maskStopLeft = 0x08; // stop on top edge
            maskStopRight = 0x02; // stop on bottom edge
#endif
        }
        if( invertedZShape )
        {
            uint temp = maskTraceLeft;
            maskTraceLeft = maskTraceRight;
            maskTraceRight = temp;
        }
        maskLeft = maskTraceLeft;
        bitsContinueLeft = maskTraceLeft;
        maskRight = maskTraceRight;
#if CMAA2_EXTRA_CONSERVATIVENESS2
        maskLeft |= maskStopLeft;
        maskRight |= maskStopRight;
#endif
        bitsContinueRight = maskTraceRight;
    }
    /////////////////////////////////////////////////////////////////////////////////////////////////////////

    bool continueLeft = true;
    bool continueRight = true;
    lineLengthLeft = 1;
    lineLengthRight = 1;

    static const uint c_maxLineLength = 86;
    [loop]
    for(int j = 0; j < 255; j++) //for(;;) <- ReShade no like
    {
        uint edgeLeft =     LoadEdge( screenPos.xy - stepRight * float(lineLengthLeft)          , int2( 0, 0 ), msaaSampleIndex );
        uint edgeRight =    LoadEdge( screenPos.xy + stepRight * ( float(lineLengthRight) + 1 ) , int2( 0, 0 ), msaaSampleIndex );

        // stop on encountering 'stopping' edge (as defined by masks)
        continueLeft    = continueLeft  && ( ( edgeLeft & maskLeft ) == bitsContinueLeft );
        continueRight   = continueRight && ( ( edgeRight & maskRight ) == bitsContinueRight );

        lineLengthLeft += continueLeft;
        lineLengthRight += continueRight;

        lpfloat maxLR = max( lineLengthRight, lineLengthLeft );

        // both stopped? cause the search end by setting maxLR to max length.
        if( !continueLeft && !continueRight )
            maxLR = (lpfloat)c_maxLineLength;

        // either the longer one is ahead of the smaller (already stopped) one by more than a factor of x, or both
        // are stopped - end the search.
#if CMAA2_EXTRA_SHARPNESS
        if( maxLR >= min( (lpfloat)c_maxLineLength, (1.20 * min( lineLengthRight, lineLengthLeft ) - 0.20) ) )
#else
        if( maxLR >= min( (lpfloat)c_maxLineLength, (1.25 * min( lineLengthRight, lineLengthLeft ) - 0.25) ) )
#endif
            break;
    }
}

void BlendZs( uint2 screenPos, bool horizontal, bool invertedZShape, lpfloat shapeQualityScore, lpfloat lineLengthLeft, lpfloat lineLengthRight, float2 stepRight, inout uint msaaSampleIndex )
{
    float2 blendDir = ( horizontal ) ? ( float2( 0, -1 ) ) : ( float2( -1, 0 ) );

    if( invertedZShape )
        blendDir = -blendDir;

    lpfloat leftOdd = c_symmetryCorrectionOffset * lpfloat( lineLengthLeft % 2 );
    lpfloat rightOdd = c_symmetryCorrectionOffset * lpfloat( lineLengthRight % 2 );

    lpfloat dampenEffect = saturate( lpfloat(lineLengthLeft + lineLengthRight - shapeQualityScore) * c_dampeningEffect ) ;

    lpfloat loopFrom = -floor( ( lineLengthLeft + 1 ) / 2 ) + 1.0;
    lpfloat loopTo = floor( ( lineLengthRight + 1 ) / 2 );
    
    lpfloat totalLength = lpfloat(loopTo - loopFrom) + 1 - leftOdd - rightOdd;
    lpfloat lerpStep = lpfloat(1.0) / totalLength;

    lpfloat lerpFromK = (0.5 - leftOdd - loopFrom) * lerpStep;

    for( lpfloat i = loopFrom; i <= loopTo; i++ )
    {
        lpfloat lerpVal = lerpStep * i + lerpFromK;

        lpfloat secondPart = (i>0);
        lpfloat srcOffset = 1.0 - secondPart * 2.0;

        lpfloat lerpK = (lerpStep * i + lerpFromK) * srcOffset + secondPart;
        lerpK *= dampenEffect;

        float2 pixelPos = screenPos + stepRight * float(i);

        lpfloat3 colorCenter    = LoadSourceColor( pixelPos, int2( 0, 0 ), msaaSampleIndex ).rgb;
        lpfloat3 colorFrom      = LoadSourceColor( pixelPos.xy + blendDir * float(srcOffset).xx, int2( 0, 0 ), msaaSampleIndex ).rgb;
        
        lpfloat3 output = lerp( colorCenter.rgb, colorFrom.rgb, lerpK );

        StoreColorSample( pixelPos.xy, output, true, msaaSampleIndex );
    }
}

void ProcessCandidatesCS(in CSIN IN)
{
    uint2 pixelPos = IN.dispatchthreadid.xy;
    int3 loadPosCenter = int3( pixelPos, 0 );
    uint msaaSampleIndex = 0;

    uint edgesCenterPacked = LoadEdge( pixelPos, int2( 0, 0 ), msaaSampleIndex );
    lpfloat4 edges      = UnpackEdgesFlt( edgesCenterPacked );
    lpfloat4 edgesLeft  = UnpackEdgesFlt( LoadEdge( pixelPos, int2( -1, 0 ), msaaSampleIndex ) );
    lpfloat4 edgesRight = UnpackEdgesFlt( LoadEdge( pixelPos, int2(  1, 0 ), msaaSampleIndex ) );
    lpfloat4 edgesBottom= UnpackEdgesFlt( LoadEdge( pixelPos, int2( 0,  1 ), msaaSampleIndex ) );
    lpfloat4 edgesTop   = UnpackEdgesFlt( LoadEdge( pixelPos, int2( 0, -1 ), msaaSampleIndex ) );

    //simple shapes
    {
        lpfloat4 blendVal = ComputeSimpleShapeBlendValues( edges, edgesLeft, edgesRight, edgesTop, edgesBottom, true );    

        const lpfloat fourWeightSum = dot( blendVal, lpfloat4( 1, 1, 1, 1 ) );
        const lpfloat centerWeight = 1.0 - fourWeightSum;

        lpfloat3 outColor = LoadSourceColor( pixelPos, int2( 0, 0 ), msaaSampleIndex ).rgb * centerWeight;

        [flatten]
        if( blendVal.x > 0.0 )   // from left
        {
            lpfloat3 pixelL = LoadSourceColor( pixelPos, int2( -1, 0 ), msaaSampleIndex ).rgb;
            outColor.rgb += blendVal.x * pixelL;
        }
        [flatten]
        if( blendVal.y > 0.0 )   // from above
        {
            lpfloat3 pixelT = LoadSourceColor( pixelPos, int2( 0, -1 ), msaaSampleIndex ).rgb; 
            outColor.rgb += blendVal.y * pixelT;
        }
        [flatten]
        if( blendVal.z > 0.0 )   // from right
        {
            lpfloat3 pixelR = LoadSourceColor( pixelPos, int2( 1, 0 ), msaaSampleIndex ).rgb;
            outColor.rgb += blendVal.z * pixelR;
        }
        [flatten]
        if( blendVal.w > 0.0 )   // from below
        {
            lpfloat3 pixelB = LoadSourceColor( pixelPos, int2( 0, 1 ), msaaSampleIndex ).rgb;
            outColor.rgb += blendVal.w * pixelB;
        }
 
        StoreColorSample( pixelPos.xy, outColor, false, msaaSampleIndex );
    }

    //complex shapes
    {
        lpfloat invertedZScore;
        lpfloat normalZScore;
        lpfloat maxScore;
        bool horizontal = true;
        bool invertedZ = false;
        // lpfloat shapeQualityScore;    // 0 - best quality, 1 - some edges missing but ok, 2 & 3 - dubious but better than nothing

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // horizontal
        {
            lpfloat4 edgesM1P0 = edgesLeft;
            lpfloat4 edgesP1P0 = edgesRight;
            lpfloat4 edgesP2P0 = UnpackEdgesFlt( LoadEdge( pixelPos, int2(  2, 0 ), msaaSampleIndex ) );

            DetectZsHorizontal( edges, edgesM1P0, edgesP1P0, edgesP2P0, invertedZScore, normalZScore );
            maxScore = max( invertedZScore, normalZScore );

            if( maxScore > 0 )
            {
                invertedZ = invertedZScore > normalZScore;
            }
        }
        {
            // Reuse the same code for vertical (used for horizontal above), but rotate input data 90 degrees counter-clockwise, so that:
            // left     becomes     bottom
            // top      becomes     left
            // right    becomes     top
            // bottom   becomes     right

            // we also have to rotate edges, thus .argb
            lpfloat4 edgesM1P0 = edgesBottom;
            lpfloat4 edgesP1P0 = edgesTop;
            lpfloat4 edgesP2P0 = UnpackEdgesFlt( LoadEdge( pixelPos, int2( 0, -2 ), msaaSampleIndex ) );

            DetectZsHorizontal( edges.argb, edgesM1P0.argb, edgesP1P0.argb, edgesP2P0.argb, invertedZScore, normalZScore );
            lpfloat vertScore = max( invertedZScore, normalZScore );

            if( vertScore > maxScore )
            {
                maxScore = vertScore;
                horizontal = false;
                invertedZ = invertedZScore > normalZScore;
                //shapeQualityScore = floor( clamp(4.0 - maxScore, 0.0, 3.0) );
            }
        }
        if( maxScore > 0 )
        {
#if CMAA2_EXTRA_SHARPNESS
            lpfloat shapeQualityScore = round( clamp(4.0 - maxScore, 0.0, 3.0) );    // 0 - best quality, 1 - some edges missing but ok, 2 & 3 - dubious but better than nothing
#else
            lpfloat shapeQualityScore = floor( clamp(4.0 - maxScore, 0.0, 3.0) );    // 0 - best quality, 1 - some edges missing but ok, 2 & 3 - dubious but better than nothing
#endif

            const float2 stepRight = ( horizontal ) ? ( float2( 1, 0 ) ) : ( float2( 0, -1 ) );
            lpfloat lineLengthLeft, lineLengthRight;
            FindZLineLengths( lineLengthLeft, lineLengthRight, pixelPos, horizontal, invertedZ, stepRight, msaaSampleIndex );

            lineLengthLeft  -= shapeQualityScore;
            lineLengthRight -= shapeQualityScore;

            if( ( lineLengthLeft + lineLengthRight ) >= (5.0) )
            {
                BlendZs( pixelPos, horizontal, invertedZ, shapeQualityScore, lineLengthLeft, lineLengthRight, stepRight, msaaSampleIndex );
            }
        }
    }    
}

struct VSOUT
{
	float4                  vpos        : SV_Position;
    float2                  uv          : TEXCOORD0;    
};

VSOUT VS_Basic(in uint id : SV_VertexID)
{
    VSOUT o;
    o.uv.x = (id == 2) ? 2.0 : 0.0;
    o.uv.y = (id == 1) ? 2.0 : 0.0;
    o.vpos = float4(o.uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return o;
}

//this is entirely homebrew
void PSApply(in VSOUT i, out float4 o : SV_Target0)
{
#if WRITE_COLLISION_REVOLVER != 0
    float4 blenditems[4] = 
    {
        tex2D(s_workingDeferredBlendItems0, i.uv),
        tex2D(s_workingDeferredBlendItems1, i.uv),
        tex2D(s_workingDeferredBlendItems2, i.uv),
        tex2D(s_workingDeferredBlendItems3, i.uv)
    };

    float4 simpleshapes = 0;
    float4 complexshapes = 0;

    for(int j = 0; j < 4; j++)
    {
        simpleshapes += blenditems[j].w < 0.5 ? float4(blenditems[j].rgb, 1) : 0;
        complexshapes += blenditems[j].w > 0.5 ? float4(blenditems[j].rgb, 1) : 0;
    }
    //only count simple shapes once!
    if(simpleshapes.w > 0.5) simpleshapes /= simpleshapes.w; //w == 1 now
    //merge with appropriate amount of complex shapes
    simpleshapes = simpleshapes * 0.8 + 1.8 * complexshapes;
    o = simpleshapes / simpleshapes.w;
#else 
    o = tex2D(s_workingDeferredBlendItems, i.uv);
#endif
}

/*=============================================================================
	Techniques
=============================================================================*/

technique CMAA2_beta
{
	pass
    {
        ComputeShader = CS_EdgeDetect<CMAA2_CS_INPUT_KERNEL_SIZE_X, CMAA2_CS_INPUT_KERNEL_SIZE_Y>;
#if CMAA_PACK_SINGLE_SAMPLE_EDGE_TO_HALF_WIDTH != 0
    	DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, CMAA2_CS_INPUT_KERNEL_SIZE_X * 2);
#else 
        DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, CMAA2_CS_INPUT_KERNEL_SIZE_X);
#endif
    	DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, CMAA2_CS_INPUT_KERNEL_SIZE_Y);     
    }
    pass
    {
        ComputeShader = ProcessCandidatesCS<16, 16>;
        DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, 16);
    	DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, 16);
    } 
    pass
	{
		VertexShader = VS_Basic;
		PixelShader  = PSApply; 
	} 
}
