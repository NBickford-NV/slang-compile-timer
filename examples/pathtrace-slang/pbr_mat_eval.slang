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

/* @DOC_START
This file takes the incoming `GltfShadeMaterial` (material uploaded in a buffer) and
evaluates it, basically sampling the textures, and returns the struct `PbrMaterial`
which is used by the BSDF functions to evaluate and sample the material.
@DOC_END */

module pbr_mat_eval;

import dh_scn_desc;
import pbr_mat_struct;

public struct MeshState {
  public float3 N;     // Normal
  public float3 T;     // Tangent
  public float3 B;     // Bitangent
  public float3 Ng;    // Geometric normal
  public float2 tc[2]; // Texture coordinates
  public bool isInside;
};

/* @DOC_START
# `NO_TEXTURES` Define
> Define this in pbr_mat_eval.slang to use a color of `vec4(1.0f)`
> for everything instead of reading textures.
@DOC_END */
#ifndef NO_TEXTURES
#define USE_TEXTURES
#endif

float4 getTexture(Sampler2D *samplerArray, GltfTextureInfo tinfo, float2 tc[2]) {
#ifdef USE_TEXTURES
  // KHR_texture_transform
  float2 texCoord = float2(mul(float3(tc[tinfo.texCoord], 1), tinfo.uvTransform));
  return samplerArray[NonUniformResourceIndex(tinfo.index)].Sample(texCoord);
#else
  return vec4(1.0F);
#endif
}

public bool isTexturePresent(in GltfTextureInfo tinfo) { return tinfo.index > -1; }

/* @DOC_START
 * Convert PBR specular glossiness to metallic-roughness
 * @DOC_END */
public float3 convertSGToMR(float3 diffuseColor, float3 specularColor, float glossiness, out float metallic,
                            out float2 roughness) {
  // Constants
  const float dielectricSpecular = 0.04f; // F0 for dielectrics

  // Compute metallic factor
  float specularIntensity = max(specularColor.r, max(specularColor.g, specularColor.b));
  float isMetal = smoothstep(dielectricSpecular + 0.01f, dielectricSpecular + 0.05f, specularIntensity);
  metallic = isMetal;

  // Compute base color
  float3 baseColor;
  if (metallic > 0.0f) {
    // Metallic: Use specular as base color
    baseColor = specularColor;
  } else {
    // Non-metallic: Correct diffuse color for energy conservation
    baseColor = diffuseColor / (1.0f - dielectricSpecular * (1.0f - metallic));
    baseColor = clamp(baseColor, 0.0f, 1.0f); // Ensure valid color
  }

  // Compute roughness
  float r = 1.0f - glossiness;
  roughness = float2(r * r);

  return baseColor;
}

/* @DOC_START
# `MICROFACET_MIN_ROUGHNESS` Define
> Minimum roughness for microfacet models.

This protects microfacet code from dividing by 0, as well as from numerical
instability around roughness == 0. However, it also means even roughness-0
surfaces will be rendered with a tiny amount of roughness.

This value is ad-hoc; it could probably be lowered without issue.
@DOC_END */
public const float MICROFACET_MIN_ROUGHNESS = 0.0014142f;

/* @DOC_START
# Function `evaluateMaterial`
> From the incoming `material` and `mesh` info, return a `PbrMaterial` struct
> for the BSDF system.
@DOC_END */
public PbrMaterial evaluateMaterial(Sampler2D *samplerArray, GltfShadeMaterial material, MeshState state) {
  // Material Evaluated
  PbrMaterial pbrMat;

  // pbrMetallicRoughness (standard)
  if (material.usePbrSpecularGlossiness == 0) {
    // Base Color/Albedo may be defined from a base texture or a flat color
    float4 baseColor = material.pbrBaseColorFactor;
    if (isTexturePresent(material.pbrBaseColorTexture)) {
      baseColor *= getTexture(samplerArray, material.pbrBaseColorTexture, state.tc);
    }
    pbrMat.baseColor = baseColor.rgb;
    pbrMat.opacity = baseColor.a;

    // Metallic-Roughness
    float roughness = material.pbrRoughnessFactor;
    float metallic = material.pbrMetallicFactor;
    if (isTexturePresent(material.pbrMetallicRoughnessTexture)) {
      // Roughness is stored in the 'g' channel, metallic is stored in the 'b' channel.
      float4 metallicRoughnessSample = getTexture(samplerArray, material.pbrMetallicRoughnessTexture, state.tc);
      roughness *= metallicRoughnessSample.g;
      metallic *= metallicRoughnessSample.b;
    }
    roughness = max(roughness, MICROFACET_MIN_ROUGHNESS);
    pbrMat.roughness = float2(roughness * roughness); // Square roughness for the microfacet model
    pbrMat.metallic = clamp(metallic, 0.0F, 1.0F);
  } else {
    // KHR_materials_pbrSpecularGlossiness: deprecated but still used in many places
    float4 diffuse = material.pbrDiffuseFactor;
    float glossiness = material.pbrGlossinessFactor;
    float3 specular = material.pbrSpecularFactor;

    if (isTexturePresent(material.pbrDiffuseTexture)) {
      diffuse *= getTexture(samplerArray, material.pbrDiffuseTexture, state.tc);
    }

    if (isTexturePresent(material.pbrSpecularGlossinessTexture)) {
      float4 specularGlossinessSample = getTexture(samplerArray, material.pbrSpecularGlossinessTexture, state.tc);
      specular *= specularGlossinessSample.rgb;
      glossiness *= specularGlossinessSample.a;
    }

    pbrMat.baseColor = convertSGToMR(diffuse.rgb, specular, glossiness, pbrMat.metallic, pbrMat.roughness);
    pbrMat.opacity = diffuse.a;
  }

  // Occlusion Map
  pbrMat.occlusion = material.occlusionStrength;
  if (isTexturePresent(material.occlusionTexture)) {
    float occlusion = getTexture(samplerArray, material.occlusionTexture, state.tc).r;
    pbrMat.occlusion = 1.0 + pbrMat.occlusion * (occlusion - 1.0);
  }

  // Normal Map
  pbrMat.N = state.N;
  pbrMat.T = state.T;
  pbrMat.B = state.B;
  pbrMat.Ng = state.Ng;
  bool needsTangentUpdate = false;

  if (isTexturePresent(material.normalTexture)) {
    float3 normal_vector = getTexture(samplerArray, material.normalTexture, state.tc).xyz;
    normal_vector = normal_vector * 2.0F - 1.0F;
    normal_vector *= float3(material.normalTextureScale, material.normalTextureScale, 1.0F);
    float3x3 tbn = float3x3(state.T, state.B, state.N);
    pbrMat.N = normalize(mul(tbn, normal_vector)); // NOTE(nbickford): Not sure if this is the right order

    // Mark that we need to update T and B due to normal perturbation
    needsTangentUpdate = true;
  }

  // Emissive term
  pbrMat.emissive = material.emissiveFactor;
  if (isTexturePresent(material.emissiveTexture)) {
    pbrMat.emissive *= getTexture(samplerArray, material.emissiveTexture, state.tc).rgb;
  }
  pbrMat.emissive = max(float3(0.0F), pbrMat.emissive);

  // KHR_materials_specular
  // https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_specular
  pbrMat.specularColor = material.specularColorFactor;
  if (isTexturePresent(material.specularColorTexture)) {
    pbrMat.specularColor *= getTexture(samplerArray, material.specularColorTexture, state.tc).rgb;
  }

  // KHR_materials_specular
  pbrMat.specular = material.specularFactor;
  if (isTexturePresent(material.specularTexture)) {
    pbrMat.specular *= getTexture(samplerArray, material.specularTexture, state.tc).a;
  }

  // Dielectric Specular
  float ior1 = 1.0F;         // IOR of the current medium (e.g., air)
  float ior2 = material.ior; // IOR of the material
  if (state.isInside &&
      (material.thicknessFactor > 0)) // If the material is thin-walled, we don't need to consider the inside IOR.
  {
    ior1 = material.ior;
    ior2 = 1.0F;
  }
  pbrMat.ior1 = ior1;
  pbrMat.ior2 = ior2;

  // KHR_materials_transmission
  pbrMat.transmission = material.transmissionFactor;
  if (isTexturePresent(material.transmissionTexture)) {
    pbrMat.transmission *= getTexture(samplerArray, material.transmissionTexture, state.tc).r;
  }

  // KHR_materials_volume
  pbrMat.attenuationColor = material.attenuationColor;
  pbrMat.attenuationDistance = material.attenuationDistance;
  pbrMat.isThinWalled = (material.thicknessFactor == 0.0);

  // KHR_materials_clearcoat
  pbrMat.clearcoat = material.clearcoatFactor;
  pbrMat.clearcoatRoughness = material.clearcoatRoughness;
  pbrMat.Nc = pbrMat.N;
  if (isTexturePresent(material.clearcoatTexture)) {
    pbrMat.clearcoat *= getTexture(samplerArray, material.clearcoatTexture, state.tc).r;
  }
  if (isTexturePresent(material.clearcoatRoughnessTexture)) {
    pbrMat.clearcoatRoughness *= getTexture(samplerArray, material.clearcoatRoughnessTexture, state.tc).g;
  }
  if (isTexturePresent(material.clearcoatNormalTexture)) {
    float3x3 tbn = float3x3(pbrMat.T, pbrMat.B, pbrMat.Nc); // NOTE(nbickford): Not sure if this is the right order
    float3 normal_vector = getTexture(samplerArray, material.clearcoatNormalTexture, state.tc).xyz;
    normal_vector = normal_vector * 2.0F - 1.0F;
    pbrMat.Nc = normalize(mul(tbn, normal_vector));
  }
  pbrMat.clearcoatRoughness = max(pbrMat.clearcoatRoughness, 0.001F);

  // KHR_materials_iridescence
  float iridescence = material.iridescenceFactor;
  float iridescenceThickness = material.iridescenceThicknessMaximum;
  pbrMat.iridescenceIor = material.iridescenceIor;
  if (isTexturePresent(material.iridescenceTexture)) {
    iridescence *= getTexture(samplerArray, material.iridescenceTexture, state.tc).x;
  }
  if (isTexturePresent(material.iridescenceThicknessTexture)) {
    const float t = getTexture(samplerArray, material.iridescenceThicknessTexture, state.tc).y;
    iridescenceThickness = lerp(material.iridescenceThicknessMinimum, material.iridescenceThicknessMaximum, t);
  }
  pbrMat.iridescence = (iridescenceThickness > 0.0f) ? iridescence : 0.0f; // No iridescence when the thickness is zero.
  pbrMat.iridescenceThickness = iridescenceThickness;

  // KHR_materials_anisotropy
  float anisotropyStrength = material.anisotropyStrength;
  // If the anisotropyStrength == 0.0f (default), the roughness is isotropic.
  // No need to rotate the anisotropyDirection or tangent space.
  if (anisotropyStrength > 0.0F) {
    float2 anisotropyDirection = float2(1.0f, 0.0f); // By default the anisotropy strength is along the tangent.
    if (isTexturePresent(material.anisotropyTexture)) {
      const float4 anisotropyTex = getTexture(samplerArray, material.anisotropyTexture, state.tc);

      // .xy encodes the direction in (tangent, bitangent) space. Remap from [0, 1] to [-1, 1].
      anisotropyDirection = normalize(float2(anisotropyTex.xy) * 2.0f - 1.0f);
      // .z encodes the strength in range [0, 1].
      anisotropyStrength *= anisotropyTex.z;
    }

    // Adjust the roughness to account for anisotropy.
    pbrMat.roughness.x = lerp(pbrMat.roughness.y, 1.0f, anisotropyStrength * anisotropyStrength);

    // Rotate the anisotropy direction in the tangent space.
    const float s = material.anisotropyRotation.x; // Sin and Cos of the rotation angle.
    const float c = material.anisotropyRotation.y;
    anisotropyDirection = float2(c * anisotropyDirection.x + s * anisotropyDirection.y,
                                 c * anisotropyDirection.y - s * anisotropyDirection.x);

    // Update the tangent to be along the anisotropy direction in tangent space.
    const float3 T_aniso = pbrMat.T * anisotropyDirection.x + pbrMat.B * anisotropyDirection.y;

    pbrMat.T = T_aniso;
    needsTangentUpdate = true;
  }

  // Perform tangent and bitangent updates if necessary
  if (needsTangentUpdate) {
    // Ensure T, B, and N are orthonormal
    pbrMat.B = cross(pbrMat.N, pbrMat.T);
    float bitangentSign = sign(dot(state.B, pbrMat.B));
    pbrMat.B = pbrMat.B * bitangentSign;
    pbrMat.T = cross(pbrMat.B, pbrMat.N) * bitangentSign;
  }

  // KHR_materials_sheen
  pbrMat.sheenColor = material.sheenColorFactor;
  if (isTexturePresent(material.sheenColorTexture)) {
    pbrMat.sheenColor *= getTexture(samplerArray, material.sheenColorTexture, state.tc).xyz; // sRGB
  }

  pbrMat.sheenRoughness = material.sheenRoughnessFactor;
  if (isTexturePresent(material.sheenRoughnessTexture)) {
    pbrMat.sheenRoughness *= getTexture(samplerArray, material.sheenRoughnessTexture, state.tc).w;
  }
  pbrMat.sheenRoughness = max(MICROFACET_MIN_ROUGHNESS, pbrMat.sheenRoughness);

  // KHR_materials_dispersion
  pbrMat.dispersion = material.dispersion;

  // KHR_materials_diffuse_transmission
  pbrMat.diffuseTransmissionFactor = material.diffuseTransmissionFactor;
  if (isTexturePresent(material.diffuseTransmissionTexture)) {
    pbrMat.diffuseTransmissionFactor *= getTexture(samplerArray, material.diffuseTransmissionTexture, state.tc).a;
  }
  pbrMat.diffuseTransmissionColor = material.diffuseTransmissionColor;
  if (isTexturePresent(material.diffuseTransmissionColorTexture)) {
    pbrMat.diffuseTransmissionColor = getTexture(samplerArray, material.diffuseTransmissionColorTexture, state.tc).rgb;
  }

  return pbrMat;
}

// Compatibility function
PbrMaterial evaluateMaterial(Sampler2D *samplerArray, GltfShadeMaterial material, float3 normal, float3 tangent,
                             float3 bitangent, float2 texCoord) {
  float2 tcoords[2] = { texCoord, float2(0.0F) };
  MeshState mesh = MeshState(normal, tangent, bitangent, normal, tcoords, false);
  return evaluateMaterial(samplerArray, material, mesh);
}
