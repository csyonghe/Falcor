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
#include "HostDeviceSharedMacros.h"
#include "DeferredRendererCommon.hlsli"

import Material;

SamplerState gColorSampler : register(s1);
Texture2D texPosition;
Texture2D texNormal;
Texture2D texBaseColor;
Texture2D texSpecRoughness;
Texture2D texLighting;

struct PsOut
{
    float4 color : SV_TARGET0;
};

// work-around compiler bugs
typedef StandardBxDF<DiffuseBrdfFrostbite> BRDFType;
typedef ShadingPoint<BRDFType > ShadingPointType;

PsOut main(float2 texC  : TEXCOORD)
{
    PsOut psOut;
    GBufferElement gBufElem;
    gBufElem.position = texPosition.Sample(gColorSampler, texC).xyz;
    gBufElem.normal= texNormal.Sample(gColorSampler, texC).xyz;
    gBufElem.baseColor= texBaseColor.Sample(gColorSampler, texC).xyz;
    float4 specRough = texSpecRoughness.Sample(gColorSampler, texC);
    gBufElem.specular = specRough.xyz;
    gBufElem.roughness = specRough.w;
    gBufElem.intrinsicLighting= texLighting.Sample(gColorSampler, texC).xyz;

    
    ShadingPointType sd;
    sd = loadStandardShadingPointFromGBuffer<DiffuseBrdfFrostbite>(gBufElem, gCamera);

    float4 finalColor = float4(0, 0, 0, 1);

    finalColor.rgb += evalMaterial<BRDFType, TLightCollection>(sd, gLightEnv).color.rgb;
   
    psOut.color = finalColor;
    return psOut;
}
