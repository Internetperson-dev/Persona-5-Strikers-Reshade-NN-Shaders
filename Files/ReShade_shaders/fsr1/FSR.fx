#include "ReShade.fxh"

//-------------------------------------------------------------
// SETTINGS
//-------------------------------------------------------------

uniform float Sharpness <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "RCAS Sharpness";
> = 0.2;

uniform float2 RenderSize <
    ui_type = "drag";
    ui_label = "Input Resolution (manual if needed)";
> = float2(1920.0, 1080.0);

//-------------------------------------------------------------
// RCAS CONSTANTS
//-------------------------------------------------------------

#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0))

float FsrRcasCon(float sharpness)
{
    return exp2(-sharpness);
}

//-------------------------------------------------------------
// TEXTURE SAMPLE
//-------------------------------------------------------------

float3 LoadColor(float2 uv)
{
    return tex2D(ReShade::BackBuffer, uv).rgb;
}

//-------------------------------------------------------------
// RCAS (sharpen pass)
//-------------------------------------------------------------

float3 FsrRcasF(float2 uv, float con)
{
    float2 texel = BUFFER_RCP_WIDTH > 0 ? float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT) : 1.0 / RenderSize;

    float3 b = LoadColor(uv + float2(0, -texel.y));
    float3 d = LoadColor(uv + float2(-texel.x, 0));
    float3 e = LoadColor(uv);
    float3 f = LoadColor(uv + float2(texel.x, 0));
    float3 h = LoadColor(uv + float2(0, texel.y));

    float bL = dot(b, float3(0.299, 0.587, 0.114));
    float dL = dot(d, float3(0.299, 0.587, 0.114));
    float eL = dot(e, float3(0.299, 0.587, 0.114));
    float fL = dot(f, float3(0.299, 0.587, 0.114));
    float hL = dot(h, float3(0.299, 0.587, 0.114));

    float nz = 0.25 * (bL + dL + fL + hL) - eL;

    float mn = min(min(bL, dL), min(fL, hL));
    float mx = max(max(bL, dL), max(fL, hL));

    nz = saturate(abs(nz) / (mx - mn + 1e-5));
    nz = 1.0 - 0.5 * nz;

    float3 min4 = min(b, min(f, h));
    float3 max4 = max(b, max(f, h));

    float3 lobe = clamp(e - (b + d + f + h) * 0.25, -FSR_RCAS_LIMIT, 0.0) * con;

    return saturate((b + d + f + h) * lobe + e);
}

//-------------------------------------------------------------
// SIMPLE UPSCALE (EASU approximation)
//-------------------------------------------------------------

float3 EASU_Simple(float2 uv, float2 scale)
{
    float2 texel = 1.0 / RenderSize;

    float2 srcUV = uv / scale;

    float3 c  = LoadColor(srcUV);
    float3 cx = LoadColor(srcUV + float2(texel.x, 0));
    float3 cy = LoadColor(srcUV + float2(0, texel.y));
    float3 cxx = LoadColor(srcUV - float2(texel.x, 0));
    float3 cyy = LoadColor(srcUV - float2(0, texel.y));

    float3 avg = (c + cx + cy + cxx + cyy) * 0.2;

    float edge = saturate(length(c - avg) * 2.0);

    return lerp(avg, c, edge);
}

//-------------------------------------------------------------
// MAIN PASS
//-------------------------------------------------------------

float4 PS_FSR1(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float scale = max(RenderSize.x / BUFFER_WIDTH, RenderSize.y / BUFFER_HEIGHT);

    float2 scaledUV = uv;

    float3 col = EASU_Simple(uv, scale);

    float con = FsrRcasCon(Sharpness);
    col = FsrRcasF(uv, con);

    return float4(col, 1.0);
}

//-------------------------------------------------------------
// TECHNIQUE
//-------------------------------------------------------------

technique FSR1_Standalone
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_FSR1;
    }
}
