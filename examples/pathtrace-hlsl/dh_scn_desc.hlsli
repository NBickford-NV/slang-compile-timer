/*
 * Copyright (c) 2022-2025, NVIDIA CORPORATION.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-FileCopyrightText: Copyright (c) 2022-2025, NVIDIA CORPORATION.
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

/* @DOC_START
Common structures used to store glTF scenes in GPU buffers.
@DOC_END */

#include "dh_lighting.hlsli"

// This is the GLTF Node structure, but flattened
struct RenderNode
{
    float4x4 worldToObject;
    float4x4 objectToWorld;
    int materialID;
    int renderPrimID;
};

// This is all the information about a vertex buffer.
// NOTE(nbickford): In the HLSL port, these are bindless resource indices, so
// one would use, for instance, StructuredBuffer<float3> positions = ResourceDescriptorHeap[positionDescIdx];
// Example: https://rtarun9.github.io/blogs/bindless_rendering/
struct VertexBuffers
{
    uint positionDescIdx; // Points to StructuredBuffer<float3>
    uint normalDescIdx; // Points to StructuredBuffer<float3>
    uint colorDescIdx; // Points to StructuredBuffer<uint>; each uint is a uint8_t4_packed.
    uint tangentDescIdx; // Points to StructuredBuffer<float4>
    uint texCoord0DescIdx; // Points to StructuredBuffer<float2>
    uint texCoord1DescIdx; // Points to StructuredBuffer<float2>
};

// This is the GLTF Primitive structure
struct RenderPrimitive
{
    uint indexDescIdx; // Points to StructuredBuffer<uint32_t>
    VertexBuffers vertexBuffer;
};

// alphaMode
static const uint ALPHA_OPAQUE = 0;
static const uint ALPHA_MASK = 1;
static const uint ALPHA_BLEND = 2;
struct GltfTextureInfo
{
    float3x2 uvTransform; // 24 bytes (2x3 matrix)
    int index; // 4 bytes; points to 
    int texCoord; // 4 bytes
}; // Total: 32 bytes

struct GltfShadeMaterial
{
    float4 pbrBaseColorFactor; // offset 0   - 16 bytes    - glTF Core
    float3 emissiveFactor; // offset 16  - 12 bytes
    float normalTextureScale; // offset 28  - 4 bytes
    float pbrRoughnessFactor; // offset 32  - 4 bytes
    float pbrMetallicFactor; // offset 36  - 4 bytes
    int alphaMode; // offset 40  - 4 bytes
    float alphaCutoff; // offset 44  - 4 bytes
    float transmissionFactor; // offset 48  - 4 bytes    - KHR_materials_transmission
    float ior; // offset 52  - 4 bytes    - KHR_materials_ior
    float3 attenuationColor; // offset 56  - 12 bytes   - KHR_materials_volume
    float thicknessFactor; // offset 68  - 4 bytes
    float attenuationDistance; // offset 72  - 4 bytes
    float clearcoatFactor; // offset 76  - 4 bytes    - KHR_materials_clearcoat
    float clearcoatRoughness; // offset 80  - 4 bytes
    float3 specularColorFactor; // offset 84  - 12 bytes   - KHR_materials_specular
    float specularFactor; // offset 96  - 4 bytes
    int unlit; // offset 100 - 4 bytes    - KHR_materials_unlit
    float iridescenceFactor; // offset 104 - 4 bytes    - KHR_materials_iridescence
    float iridescenceThicknessMaximum; // offset 108 - 4 bytes
    float iridescenceThicknessMinimum; // offset 112 - 4 bytes
    float iridescenceIor; // offset 116 - 4 bytes
    float anisotropyStrength; // offset 120 - 4 bytes    - KHR_materials_anisotropy
    float2 anisotropyRotation; // offset 124 - 8 bytes
    float sheenRoughnessFactor; // offset 132 - 4 bytes    - KHR_materials_sheen
    float3 sheenColorFactor; // offset 136 - 12 bytes
    float occlusionStrength; // offset 148 - 4 bytes
    float dispersion; // offset 152 - 4 bytes    - KHR_materials_dispersion
    float4 pbrDiffuseFactor; // offset 156 - 16 bytes   - KHR_materials_pbrSpecularGlossiness
    float3 pbrSpecularFactor; // offset 172 - 12 bytes
    int usePbrSpecularGlossiness; // offset 184 - 4 bytes
    float pbrGlossinessFactor; // offset 188 - 4 bytes
    float3 diffuseTransmissionColor; // offset 192 - 12 bytes   - KHR_materials_diffuse_transmission
    float diffuseTransmissionFactor; // offset 204 - 4 bytes
    int pad; // offset 208 - 4 bytes (padding for alignment)

  // Texture infos (32 bytes each)
    GltfTextureInfo pbrBaseColorTexture;
    GltfTextureInfo normalTexture;
    GltfTextureInfo pbrMetallicRoughnessTexture;
    GltfTextureInfo emissiveTexture;
    GltfTextureInfo transmissionTexture;
    GltfTextureInfo thicknessTexture;
    GltfTextureInfo clearcoatTexture;
    GltfTextureInfo clearcoatRoughnessTexture;
    GltfTextureInfo clearcoatNormalTexture;
    GltfTextureInfo specularTexture;
    GltfTextureInfo specularColorTexture;
    GltfTextureInfo iridescenceTexture;
    GltfTextureInfo iridescenceThicknessTexture;
    GltfTextureInfo anisotropyTexture;
    GltfTextureInfo sheenColorTexture;
    GltfTextureInfo sheenRoughnessTexture;
    GltfTextureInfo occlusionTexture;
    GltfTextureInfo pbrDiffuseTexture;
    GltfTextureInfo pbrSpecularGlossinessTexture;
    GltfTextureInfo diffuseTransmissionTexture; //
    GltfTextureInfo diffuseTransmissionColorTexture; //
}; // Total size: 884 bytes

GltfTextureInfo defaultGltfTextureInfo()
{
    GltfTextureInfo t;
    t.uvTransform = float3x2(float2(1, 0), float2(0, 1), float2(0, 0));
    t.index = -1;
    t.texCoord = 0;
    return t;
}

GltfShadeMaterial defaultGltfMaterial()
{
    GltfShadeMaterial m;
    m.pbrBaseColorFactor = float4(1, 1, 1, 1);
    m.emissiveFactor = float3(0, 0, 0);
    m.normalTextureScale = 1;
    m.pbrRoughnessFactor = 1;
    m.pbrMetallicFactor = 1;
    m.alphaMode = ALPHA_OPAQUE;
    m.alphaCutoff = 0.5;
    m.transmissionFactor = 0;
    m.ior = 1.5;
    m.attenuationColor = float3(1, 1, 1);
    m.thicknessFactor = 0;
    m.attenuationDistance = 0;
    m.clearcoatFactor = 0;
    m.clearcoatRoughness = 0;
    m.specularFactor = 0;
    m.specularColorFactor = float3(1, 1, 1);
    m.unlit = 0;
    m.iridescenceFactor = 0;
    m.iridescenceThicknessMaximum = 100;
    m.iridescenceThicknessMinimum = 400;
    m.iridescenceIor = 1.3f;
    m.anisotropyStrength = 0;
    m.anisotropyRotation = float2(0, 0);
    m.sheenRoughnessFactor = 0;
    m.sheenColorFactor = float3(0, 0, 0);
    m.occlusionStrength = 1;
    m.dispersion = 0;
    m.usePbrSpecularGlossiness = 0;
    m.pbrDiffuseFactor = float4(1, 1, 1, 1);
    m.pbrSpecularFactor = float3(1, 1, 1);
    m.pbrGlossinessFactor = 1;
    m.diffuseTransmissionColor = float3(1, 1, 1);
    m.diffuseTransmissionFactor = 0;

    m.pbrBaseColorTexture = defaultGltfTextureInfo();
    m.normalTexture = defaultGltfTextureInfo();
    m.pbrMetallicRoughnessTexture = defaultGltfTextureInfo();
    m.emissiveTexture = defaultGltfTextureInfo();
    m.transmissionTexture = defaultGltfTextureInfo();
    m.thicknessTexture = defaultGltfTextureInfo();
    m.clearcoatTexture = defaultGltfTextureInfo();
    m.clearcoatRoughnessTexture = defaultGltfTextureInfo();
    m.clearcoatNormalTexture = defaultGltfTextureInfo();
    m.specularTexture = defaultGltfTextureInfo();
    m.specularColorTexture = defaultGltfTextureInfo();
    m.iridescenceTexture = defaultGltfTextureInfo();
    m.iridescenceThicknessTexture = defaultGltfTextureInfo();
    m.anisotropyTexture = defaultGltfTextureInfo();
    m.sheenColorTexture = defaultGltfTextureInfo();
    m.sheenRoughnessTexture = defaultGltfTextureInfo();
    m.pbrDiffuseTexture = defaultGltfTextureInfo();
    m.pbrSpecularGlossinessTexture = defaultGltfTextureInfo();

    return m;
}

// The scene description is a pointer to the material, render node and render primitive
// The buffers are all arrays of the above structures
struct SceneDescription
{
    uint materialDescIdx; // StructuredBuffer<GltfShadeMaterial>
    uint renderNodeDescIdx; // StructuredBuffer<RenderNode>
    uint renderPrimitiveDescIdx; // StructuredBuffer<RenderPrimitive>
    uint lightDescIdx; // StructuredBuffer<Light>
    int numLights; // number of punctual lights
};
