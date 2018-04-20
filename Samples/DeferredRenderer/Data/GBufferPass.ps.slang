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
#include "DeferredRendererCommon.hlsli"

import Material;

SamplerState gSampler;

struct PsOut
{
    float3 posW;
    float4 normal;
    float4 baseColor;
    float4 specularRoughness;
    float3 intrinsicLighting;
};

PsOut main(MainVsOut vOut, float4 pixelCrd : SV_POSITION) : SV_TARGET
{
    PsOut psOut;

    ShadingData sd = prepareShadingData<TMaterial>(vOut.vsData, gMaterial, gCamera.posW);

    GBufferElement gbufElem = packGBuffer<TMaterial.BxDF>(sd);
    psOut.posW = gbufElem.position;
    psOut.normal = float4(gbufElem.normal, 0.0);
    psOut.baseColor = float4(gbufElem.baseColor.rgb, 0.0);
    psOut.specularRoughness = float4(gbufElem.specular, gbufElem.roughness);
    psOut.intrinsicLighting = gbufElem.intrinsicLighting;
    return psOut;
}
