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

module dh_scn_desc;

/* @DOC_START
Common structures used to store glTF scenes in GPU buffers.
@DOC_END */

import dh_lighting;

// This is the GLTF Node structure, but flattened
public struct RenderNode {
  public float4x4 worldToObject;
  public float4x4 objectToWorld;
  public int materialID;
  public int renderPrimID;
};

// This is all the information about a vertex buffer
public struct VertexBuffers {
  public float3 *positionAddress;
  public float3 *normalAddress;
  public uint8_t4_packed *colorAddress;
  public float4 *tangentAddress;
  public float2 *texCoord0Address;
  public float2 *texCoord1Address;
};

// This is the GLTF Primitive structure
public struct RenderPrimitive {
  public uint32_t *indexAddress;
  public VertexBuffers vertexBuffer;
};

// alphaMode
public const uint ALPHA_OPAQUE = 0;
public const uint ALPHA_MASK = 1;
public const uint ALPHA_BLEND = 2;
public struct GltfTextureInfo {
  public float3x2 uvTransform; // 24 bytes (2x3 matrix)
  public int index;            // 4 bytes
  public int texCoord;         // 4 bytes
}; // Total: 32 bytes

public struct GltfShadeMaterial {
  public float4 pbrBaseColorFactor;         // offset 0   - 16 bytes    - glTF Core
  public float3 emissiveFactor;             // offset 16  - 12 bytes
  public float normalTextureScale;          // offset 28  - 4 bytes
  public float pbrRoughnessFactor;          // offset 32  - 4 bytes
  public float pbrMetallicFactor;           // offset 36  - 4 bytes
  public int alphaMode;                     // offset 40  - 4 bytes
  public float alphaCutoff;                 // offset 44  - 4 bytes
  public float transmissionFactor;          // offset 48  - 4 bytes    - KHR_materials_transmission
  public float ior;                         // offset 52  - 4 bytes    - KHR_materials_ior
  public float3 attenuationColor;           // offset 56  - 12 bytes   - KHR_materials_volume
  public float thicknessFactor;             // offset 68  - 4 bytes
  public float attenuationDistance;         // offset 72  - 4 bytes
  public float clearcoatFactor;             // offset 76  - 4 bytes    - KHR_materials_clearcoat
  public float clearcoatRoughness;          // offset 80  - 4 bytes
  public float3 specularColorFactor;        // offset 84  - 12 bytes   - KHR_materials_specular
  public float specularFactor;              // offset 96  - 4 bytes
  public int unlit;                         // offset 100 - 4 bytes    - KHR_materials_unlit
  public float iridescenceFactor;           // offset 104 - 4 bytes    - KHR_materials_iridescence
  public float iridescenceThicknessMaximum; // offset 108 - 4 bytes
  public float iridescenceThicknessMinimum; // offset 112 - 4 bytes
  public float iridescenceIor;              // offset 116 - 4 bytes
  public float anisotropyStrength;          // offset 120 - 4 bytes    - KHR_materials_anisotropy
  public float2 anisotropyRotation;         // offset 124 - 8 bytes
  public float sheenRoughnessFactor;        // offset 132 - 4 bytes    - KHR_materials_sheen
  public float3 sheenColorFactor;           // offset 136 - 12 bytes
  public float occlusionStrength;           // offset 148 - 4 bytes
  public float dispersion;                  // offset 152 - 4 bytes    - KHR_materials_dispersion
  public float4 pbrDiffuseFactor;           // offset 156 - 16 bytes   - KHR_materials_pbrSpecularGlossiness
  public float3 pbrSpecularFactor;          // offset 172 - 12 bytes
  public int usePbrSpecularGlossiness;      // offset 184 - 4 bytes
  public float pbrGlossinessFactor;         // offset 188 - 4 bytes
  public float3 diffuseTransmissionColor;   // offset 192 - 12 bytes   - KHR_materials_diffuse_transmission
  public float diffuseTransmissionFactor;   // offset 204 - 4 bytes
  int pad;                                  // offset 208 - 4 bytes (padding for alignment)

  // Texture infos (32 bytes each)
  public GltfTextureInfo pbrBaseColorTexture;
  public GltfTextureInfo normalTexture;
  public GltfTextureInfo pbrMetallicRoughnessTexture;
  public GltfTextureInfo emissiveTexture;
  public GltfTextureInfo transmissionTexture;
  public GltfTextureInfo thicknessTexture;
  public GltfTextureInfo clearcoatTexture;
  public GltfTextureInfo clearcoatRoughnessTexture;
  public GltfTextureInfo clearcoatNormalTexture;
  public GltfTextureInfo specularTexture;
  public GltfTextureInfo specularColorTexture;
  public GltfTextureInfo iridescenceTexture;
  public GltfTextureInfo iridescenceThicknessTexture;
  public GltfTextureInfo anisotropyTexture;
  public GltfTextureInfo sheenColorTexture;
  public GltfTextureInfo sheenRoughnessTexture;
  public GltfTextureInfo occlusionTexture;
  public GltfTextureInfo pbrDiffuseTexture;
  public GltfTextureInfo pbrSpecularGlossinessTexture;
  public GltfTextureInfo diffuseTransmissionTexture;      //
  public GltfTextureInfo diffuseTransmissionColorTexture; //
}; // Total size: 884 bytes

public GltfTextureInfo defaultGltfTextureInfo() {
  GltfTextureInfo t;
  t.uvTransform = float3x2(float2(1, 0), float2(0, 1), float2(0, 0));
  t.index = -1;
  t.texCoord = 0;
  return t;
}

public GltfShadeMaterial defaultGltfMaterial() {
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
  m.pbrDiffuseFactor = float4(1);
  m.pbrSpecularFactor = float3(1);
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
public struct SceneDescription {
  public GltfShadeMaterial *materialAddress;
  public RenderNode *renderNodeAddress;
  public RenderPrimitive *renderPrimitiveAddress;
  public Light *lightAddress;
  public int numLights; // number of punctual lights
};
