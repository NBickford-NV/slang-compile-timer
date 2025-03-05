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

/// @DOC_SKIP

module pbr_mat_struct;

import func;

public struct PbrMaterial {
  public float3 baseColor; // base color
  public float opacity;    // 1 = opaque, 0 = fully transparent
  public float2 roughness; // 0 = smooth, 1 = rough (anisotropic: x = U, y = V)
  public float metallic;   // 0 = dielectric, 1 = metallic
  public float3 emissive;  // emissive color
  public float occlusion;  // occlusion factor

  public float3 N;  // shading normal
  public float3 T;  // shading normal
  public float3 B;  // shading normal
  public float3 Ng; // geometric normal

  public float ior1;       // index of refraction : current medium (i.e. air)
  public float ior2;       // index of refraction : the other side (i.e. glass)
  public float dispersion; // KHR_materials_specular

  public float specular;       // weight of the dielectric specular layer
  public float3 specularColor; // color of the dielectric specular layer
  public float transmission;   // KHR_materials_transmission

  public float3 attenuationColor;   // KHR_materials_volume
  public float attenuationDistance; //
  public bool isThinWalled;         // Replace for isThinWalled?

  public float clearcoat;          // KHR_materials_clearcoat
  public float clearcoatRoughness; //
  public float3 Nc;                // clearcoat normal

  public float iridescence;
  public float iridescenceIor;
  public float iridescenceThickness;

  public float3 sheenColor;
  public float sheenRoughness;

  public float diffuseTransmissionFactor;
  public float3 diffuseTransmissionColor;
};

public PbrMaterial defaultPbrMaterial() {
  PbrMaterial mat;
  mat.baseColor = float3(1.0F);
  mat.opacity = 1.0F;
  mat.roughness = float2(1.0F);
  mat.metallic = 1.0F;
  mat.emissive = float3(0.0F);

  mat.N = float3(0.0F, 0.0F, 1.0F);
  mat.Ng = float3(0.0F, 0.0F, 1.0F);
  mat.T = float3(1.0F, 0.0F, 0.0F);
  mat.B = float3(0.0F, 1.0F, 0.0F);

  mat.ior1 = 1.0F;
  mat.ior2 = 1.5F;
  mat.dispersion = 0.0F;

  mat.specular = 1.0F;
  mat.specularColor = float3(1.0F);
  mat.transmission = 0.0F;

  mat.attenuationColor = float3(1.0F);
  mat.attenuationDistance = 1.0F;
  mat.isThinWalled = true;

  mat.clearcoat = 0.0F;
  mat.clearcoatRoughness = 0.01F;
  mat.Nc = float3(0.0F, 0.0F, 1.0F);

  mat.iridescence = 0.0F;
  mat.iridescenceIor = 1.5F;
  mat.iridescenceThickness = 0.1F;

  mat.sheenColor = float3(0.0F);
  mat.sheenRoughness = 0.0F;
  mat.occlusion = 1.0F;

  mat.diffuseTransmissionFactor = 0.0F;
  mat.diffuseTransmissionColor = float3(1.0F);

  return mat;
}

public PbrMaterial defaultPbrMaterial(float3 baseColor, float metallic, float roughness, float3 N, float3 Ng) {
  PbrMaterial mat = defaultPbrMaterial();
  mat.baseColor = baseColor;
  mat.metallic = metallic;
  mat.roughness = float2(roughness * roughness);
  mat.Ng = Ng;
  mat.N = N;
  orthonormalBasis(mat.N, mat.T, mat.B);

  return mat;
}
