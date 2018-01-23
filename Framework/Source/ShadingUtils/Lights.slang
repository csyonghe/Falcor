/***************************************************************************
# Copyright (c) 2015, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
***************************************************************************/

#ifndef _FALCOR_LIGHTS_H_
#define _FALCOR_LIGHTS_H_

__import Helpers;

// Make sure we get the macros like `_fn` and `_ref`
// TODO: just eliminate these since we know this is pure Slang.
#include "HostDeviceData.h"

/*******************************************************************
                    Lights
*******************************************************************/

/**
This stores the information about the current light source at the shading point.
This includes a direction from a shading point towards the light,
radiance emitted from the light souce, which is *received* at the shading point.
*/
struct LightAttribs
{
    float3	L;				///< Normalized direction to the light at shading hit
    float   shadowFactor;   ///< Shadow factor
    float3	lightIntensity;	///< Radiance of the emitted light at shading hit

    float3    P;              ///< Sampled point on the light source
    float3    N;              ///< Normal of the sampled point on the light source
    float   pdf;            ///< Probability density function of sampling the light source
    //AREA_LIGHT_EXTENSION
    int       lightType;
    float3    points[4];
};

/**
    This routine computes the position of the the light based on the point 'shadingPosition'.
*/
inline float3 _fn getLightPos(LightData Light, float3 shadingPosition)
{
    float3 lightPos = Light.worldPos;
    if(Light.type == LightArea)
    {
        lightPos = mul(float4(lightPos, 1.0), Light.transMat).xyz;
    }    
    else if(Light.type == LightDirectional)
    {
        float dist = length(shadingPosition - lightPos);
        lightPos = shadingPosition - Light.worldDir * dist;
    }
    return lightPos;
}

/**
    This routine computes the radiance from the light at the point 'shadingPosition'.
*/
inline float3 _fn getLightRadiance(LightData Light, float3 shadingPosition)
{
    float3 lightRadiance = Light.intensity;
    if(Light.type == LightPoint || Light.type == LightArea)
    {
        // TODO: add point on the light for area lights
        float3 lightDir = shadingPosition - getLightPos(Light, shadingPosition);
        lightRadiance *= 1.0f / (4.0f * M_PIf);    // per steradian
        lightRadiance /= dot(lightDir, lightDir);        // per square meter
    }
    return lightRadiance;
}

/**
    This routine prepares attributes for shading a point with a particular light source.
    The outputs are an incident radiance towards the shading point 
    and the direction from the shading point towards the light source.
*/
inline void _fn prepareLightAttribs(LightData Light, ShadingAttribs ShAttr, float shadowFactor, _ref(LightAttribs) LightAttr)
{
    /* Evaluate direction to the light */
    LightAttr.P = getLightPos(Light, ShAttr.P);
    LightAttr.pdf = 0;
    LightAttr.N = 0;
    LightAttr.shadowFactor = shadowFactor;

    [unroll]
    for(uint i = 0 ; i < 4 ; i++)
    {
        LightAttr.points[i] = 0;
    }
    float3 PosToLight = LightAttr.P - ShAttr.P;
    if(dot(PosToLight, PosToLight) > 1e-3f)
    {
        LightAttr.L = normalize(PosToLight);
    }
    else
    {
        LightAttr.L = 0;
    }
    LightAttr.lightIntensity = Light.intensity;
    if(Light.type == LightDirectional)
    {
        LightAttr.L = -Light.worldDir;
    }
    else if(Light.type == LightArea || Light.type == LightPoint)
    {
        /* Evaluate various attenuation factors: cosine, 1/r^2, etc. */
        float Atten = 1.f;

        float cosTheta = -dot(LightAttr.L, Light.worldDir);	// cos of angle of light orientation with outgoing direction
        if(Light.type == LightArea)			// Cosine attenuation
        {
            Atten = max(0.f, cosTheta) * Light.surfaceArea;
        }
        else if(Light.type == LightPoint)
        {
            // Spot light cone angle
            if(cosTheta < Light.cosOpeningAngle)
                Atten = 0.f;
            if(Light.penumbraAngle > 0.f)	// Compute cone attenuation of a spot light
            {
                float deltaAngle = Light.openingAngle - acos(cosTheta);
                Atten *= clamp((deltaAngle - Light.penumbraAngle) / Light.penumbraAngle, 0.f, 1.f);
            }
        }

        // Quadratic attenuation
        Atten /= max(1e-3f, dot(PosToLight, PosToLight));

        LightAttr.lightIntensity *= Atten;
    }
    //AREA_LIGHT_EXTENSION
    LightAttr.lightType = Light.type;
    if (Light.type == LightQuad)
    {
        $for (i in Range(4))
            LightAttr.points[i] = Light.points[i].xyz;
        LightAttr.lightIntensity = Light.intensity;
    }
    // DISABLED_FOR_D3D12
#if 0
    if (Light.type == LightArea)
    {
        for (int index = 0; index < 4; index++)
        {
            // Access the geometry buffers
            float* vertices = (float*)(Light.vertexPtr.ptr);
            // Get vertices pointed by the corresponding index
            float3 p0 = float3(vertices[index * 3 + 0], vertices[index * 3 + 1], vertices[index * 3 + 2]);

            // Apply model instance transformation matrix
            LightAttr.points[index] = float3(mul(float4(p0, 1.0), Light.transMat));
        }
    }
#endif
}

/**
    This routine samples the light source.
*/
void _fn sampleLight(float3 shadingHitPos, LightData lData, float3 rSample, _ref(LightAttribs) lAttr)
{
    // Sample the light based on its type: point, directional, or area
    switch (lData.type)
    {
        case LightPoint:
        {
            // Get the position
            lAttr.P = getLightPos(lData, shadingHitPos);

            float3 PosToLight = lAttr.P - shadingHitPos;
            float lDist = length(PosToLight);
            lAttr.L = PosToLight / max(1e-3f, lDist);

            // For point light, its normal is always along the L direction
            lAttr.N = lAttr.L;

            // Compute the intensity and the PDF
            lAttr.lightIntensity = getLightRadiance(lData, shadingHitPos);
            lAttr.pdf = 1.f;
        }
        break;

        case LightDirectional:
        {
            // Get the position
            lAttr.P = getLightPos(lData, shadingHitPos);
            lAttr.L = -lData.worldDir;

            // For directional light, its normal is always along the L direction
            lAttr.N = lAttr.L;
            
            // Compute the intensity and the PDF
            lAttr.lightIntensity = lData.intensity;
            lAttr.pdf = 1.f;
        }
        break;
    }
}

/**
This routine samples a rectangular area light source in a stratified way.
*/
void _fn stratifiedSampleRectangularAreaLight(float3 shadingHitPos, LightData lData, float2 rSample, int x, int y, int numStrataX, int numStrataY, _ref(LightAttribs) lAttr)
{
    if (lData.type != LightArea)
        return;

    // Transform light position and light normal
    float3 lightPos = mul(float4(lData.worldPos, 1.0f), lData.transMat).rgb;
    lAttr.N = mul(float4(lData.worldDir, 0.0f), lData.transMat).rgb;

    // Transform tangent frame
    float3 transformedTangent = mul(float4(lData.tangent, 0.0f), lData.transMat).rgb;
    float3 transformedBitangent = mul(float4(lData.bitangent, 0.0f), lData.transMat).rgb;

    float lightSizeY1 = length(transformedTangent);
    float lightSizeY2 = length(transformedBitangent);

    // Generate stratified samples
    float y1 = ((x + rSample.x) / float(numStrataX) - 0.5f) * lightSizeY1;
    float y2 = ((y + rSample.y) / float(numStrataY) - 0.5f) * lightSizeY2;

    lAttr.P = lightPos + y1 * normalize(transformedTangent) + y2 * normalize(transformedBitangent);

    float3 PosToLight = lAttr.P - shadingHitPos;
    float lDist = length(PosToLight);
    lAttr.L = PosToLight / max(1e-3f, lDist);

    lAttr.lightIntensity = lData.intensity;

    // Compute the PDF
    lAttr.pdf = lDist * lDist / (abs(dot(lAttr.N, lAttr.L)) * lData.surfaceArea);

    // Set light's contribution
    if (lAttr.pdf > 0.f && dot(lAttr.N, lAttr.L) < 0.f)
        lAttr.lightIntensity /= lAttr.pdf;
    else
        lAttr.lightIntensity = 0;
}


//AREA_LIGHT_EXTENSION
struct Points4
{
    float3 points[4]; 
};
struct Points5
{
    float3 points[5];
};

#define pi 3.14159265
#define LUT_SIZE 32.0
#define LUT_SCALE (LUT_SIZE - 1.0)/LUT_SIZE
#define LUT_BIAS 0.5/LUT_SIZE
Texture2D g_ltc_mat;
Texture2D g_ltc_mag;
SamplerState g_light_texSampler;

float3 evalAreaLight_diffuse(float3 N, float3 V, float3 P, float3 intensity, Points4 points, bool twoSided)
{
    float3 diffLighting = intensity*LTC_Evaluate(N, V, P, float3x3(1,0,0,0,1,0,0,0,1), points, twoSided); 
    return diffLighting;
}

float3 evalAreaLight_specular(float3 N, float3 V, float3 P, float roughness, float3 intensity, Points4 points, bool twoSided)
{
    float theta = acos(dot(N, V));
    float2 uv = float2(roughness, theta/(0.5*pi));
    uv = uv*LUT_SCALE + LUT_BIAS;
        
    float4 t = g_ltc_mat.SampleBias(g_light_texSampler, uv, 0.0);
    float3x3 Minv = float3x3(
        float3(  1,   0, t.y),
        float3(  0, t.z,   0),
        float3(t.w,   0, t.x)
    );
    float3 specLighting = intensity*LTC_Evaluate(N, V, P, Minv, points, twoSided);
    specLighting *= g_ltc_mag.SampleBias(g_light_texSampler, uv, 0.0).w;
    specLighting = float3(0.0f);
    return specLighting;
}

float3 LTC_Evaluate(float3 N, float3 V, float3 P, float3x3 Minv, Points4 p, bool twoSided)
{
    // construct orthonormal basis around N
    float3 T1, T2;
    T1 = normalize(V - N*dot(V, N));
    T2 = cross(N, T1);

    // rotate area light in (T1, T2, N) basis
    Minv = mul(transpose(float3x3(T1, T2, N)), Minv);

    // polygon (allocate 5 vertices for clipping)
    Points5 L;
    L.points[0] = mul(p.points[0] - P, Minv);
    L.points[1] = mul(p.points[1] - P, Minv);
    L.points[2] = mul(p.points[2] - P, Minv);
    L.points[3] = mul(p.points[3] - P, Minv);
    L.points[4] = float3(0,0,0);

    int n;
    ClipQuadToHorizon(L, n);
    
    if (n == 0)
        return float3(0, 0, 0);

    // project onto sphere
    L.points[0] = normalize(L.points[0]);
    L.points[1] = normalize(L.points[1]);
    L.points[2] = normalize(L.points[2]);
    L.points[3] = normalize(L.points[3]);
    L.points[4] = normalize(L.points[4]);

    // integrate
    float sum = 0.0;

    sum += IntegrateEdge(L.points[0], L.points[1]);
    sum += IntegrateEdge(L.points[1], L.points[2]);
    sum += IntegrateEdge(L.points[2], L.points[3]);
    if (n >= 4)
        sum += IntegrateEdge(L.points[3], L.points[4]);
    if (n == 5)
        sum += IntegrateEdge(L.points[4], L.points[0]);

    sum = twoSided ? abs(sum) : max(0.0, sum);

    float3 Lo_i = float3(sum, sum, sum);

    return Lo_i;
}

float IntegrateEdge(float3 v1, float3 v2)
{
    float cosTheta = dot(v1, v2);
    float theta = acos(cosTheta);    
    float res = cross(v1, v2).z * ((theta > 0.001) ? theta/sin(theta) : 1.0);

    return res;
}

void ClipQuadToHorizon(inout Points5 L, out int n)
{
    // detect clipping config
    int config = 0;
    if (L.points[0].z > 0.0) config += 1;
    if (L.points[1].z > 0.0) config += 2;
    if (L.points[2].z > 0.0) config += 4;
    if (L.points[3].z > 0.0) config += 8;

    // clip
    n = 0;

    if (config == 0)
    {
        // clip all
    }
    else if (config == 1) // V1 clip V2 V3 V4
    {
        n = 3;
        L.points[1] = -L.points[1].z * L.points[0] + L.points[0].z * L.points[1];
        L.points[2] = -L.points[3].z * L.points[0] + L.points[0].z * L.points[3];
    }
    else if (config == 2) // V2 clip V1 V3 V4
    {
        n = 3;
        L.points[0] = -L.points[0].z * L.points[1] + L.points[1].z * L.points[0];
        L.points[2] = -L.points[2].z * L.points[1] + L.points[1].z * L.points[2];
    }
    else if (config == 3) // V1 V2 clip V3 V4
    {
        n = 4;
        L.points[2] = -L.points[2].z * L.points[1] + L.points[1].z * L.points[2];
        L.points[3] = -L.points[3].z * L.points[0] + L.points[0].z * L.points[3];
    }
    else if (config == 4) // V3 clip V1 V2 V4
    {
        n = 3;
        L.points[0] = -L.points[3].z * L.points[2] + L.points[2].z * L.points[3];
        L.points[1] = -L.points[1].z * L.points[2] + L.points[2].z * L.points[1];
    }
    else if (config == 5) // V1 V3 clip V2 V4) impossible
    {
        n = 0;
    }
    else if (config == 6) // V2 V3 clip V1 V4
    {
        n = 4;
        L.points[0] = -L.points[0].z * L.points[1] + L.points[1].z * L.points[0];
        L.points[3] = -L.points[3].z * L.points[2] + L.points[2].z * L.points[3];
    }
    else if (config == 7) // V1 V2 V3 clip V4
    {
        n = 5;
        L.points[4] = -L.points[3].z * L.points[0] + L.points[0].z * L.points[3];
        L.points[3] = -L.points[3].z * L.points[2] + L.points[2].z * L.points[3];
    }
    else if (config == 8) // V4 clip V1 V2 V3
    {
        n = 3;
        L.points[0] = -L.points[0].z * L.points[3] + L.points[3].z * L.points[0];
        L.points[1] = -L.points[2].z * L.points[3] + L.points[3].z * L.points[2];
        L.points[2] =  L.points[3];
    }
    else if (config == 9) // V1 V4 clip V2 V3
    {
        n = 4;
        L.points[1] = -L.points[1].z * L.points[0] + L.points[0].z * L.points[1];
        L.points[2] = -L.points[2].z * L.points[3] + L.points[3].z * L.points[2];
    }
    else if (config == 10) // V2 V4 clip V1 V3) impossible
    {
        n = 0;
    }
    else if (config == 11) // V1 V2 V4 clip V3
    {
        n = 5;
        L.points[4] = L.points[3];
        L.points[3] = -L.points[2].z * L.points[3] + L.points[3].z * L.points[2];
        L.points[2] = -L.points[2].z * L.points[1] + L.points[1].z * L.points[2];
    }
    else if (config == 12) // V3 V4 clip V1 V2
    {
        n = 4;
        L.points[1] = -L.points[1].z * L.points[2] + L.points[2].z * L.points[1];
        L.points[0] = -L.points[0].z * L.points[3] + L.points[3].z * L.points[0];
    }
    else if (config == 13) // V1 V3 V4 clip V2
    {
        n = 5;
        L.points[4] = L.points[3];
        L.points[3] = L.points[2];
        L.points[2] = -L.points[1].z * L.points[2] + L.points[2].z * L.points[1];
        L.points[1] = -L.points[1].z * L.points[0] + L.points[0].z * L.points[1];
    }
    else if (config == 14) // V2 V3 V4 clip V1
    {
        n = 5;
        L.points[4] = -L.points[0].z * L.points[3] + L.points[3].z * L.points[0];
        L.points[0] = -L.points[0].z * L.points[1] + L.points[1].z * L.points[0];
    }
    else if (config == 15) // V1 V2 V3 V4
    {
        n = 4;
    }
    
    if (n == 3)
        L.points[3] = L.points[0];
    if (n == 4)
        L.points[4] = L.points[0];
}


////////////


#endif	// _FALCOR_LIGHTS_H_
