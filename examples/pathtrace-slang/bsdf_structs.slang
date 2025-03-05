/*
 * Copyright (c) 2023-2025, NVIDIA CORPORATION.  All rights reserved.
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
 * SPDX-FileCopyrightText: Copyright (c) 2023-2025, NVIDIA CORPORATION.
 * SPDX-License-Identifier: Apache-2.0
 */

module bsdf_structs;

/* @DOC_START
# `BSDF_EVENT*` Defines
> These are the flags of the `BsdfSampleData::event_type` bitfield, which
> indicates the type of lobe that was sampled.

This terminology is based on McGuire et al., "A Taxonomy of Bidirectional
Scattering Distribution Function Lobes for Rendering Engineers",
https://casual-effects.com/research/McGuire2020BSDF/McGuire2020BSDF.pdf.
@DOC_END */

// Individual flags:
public const uint BSDF_EVENT_ABSORB = 0; // 0: invalid sample; path should be discarded (radiance 0)
public const uint BSDF_EVENT_DIFFUSE = 1; // 1: e.g. Lambert. Lobe is always centered on the surface normal.
public const uint BSDF_EVENT_GLOSSY =
    (1 << 1); // 2; Center of lobe depends on viewing angle; not perfectly specular reflection.
public const uint BSDF_EVENT_IMPULSE = (1 << 2); // 4; "Perfectly specular" or "mirror-like" reflection or transmission.
public const uint BSDF_EVENT_REFLECTION =
    (1 << 3); // 8; Both view and light directions are on the same side of the geometric normal.
public const uint BSDF_EVENT_TRANSMISSION =
    (1 << 4); // 16; View and light directions are on opposite sides of the geometric normal.

// Combinations:
public const uint BSDF_EVENT_DIFFUSE_REFLECTION = (BSDF_EVENT_DIFFUSE | BSDF_EVENT_REFLECTION);    // 9
public const uint BSDF_EVENT_DIFFUSE_TRANSMISSION = (BSDF_EVENT_DIFFUSE | BSDF_EVENT_TRANSMISSION); // 17
public const uint BSDF_EVENT_GLOSSY_REFLECTION = (BSDF_EVENT_GLOSSY | BSDF_EVENT_REFLECTION);       // 10
public const uint BSDF_EVENT_GLOSSY_TRANSMISSION = (BSDF_EVENT_GLOSSY | BSDF_EVENT_TRANSMISSION);   // 18
public const uint BSDF_EVENT_IMPULSE_REFLECTION = (BSDF_EVENT_IMPULSE | BSDF_EVENT_REFLECTION);     // 12
public const uint BSDF_EVENT_IMPULSE_TRANSMISSION = (BSDF_EVENT_IMPULSE | BSDF_EVENT_TRANSMISSION); // 20

/** @DOC_START
# struct `BsdfEvaluateData`
> Data structure for evaluating a BSDF. See the file for parameter documentation.
@DOC_END */
public struct BsdfEvaluateData {
  public float3 k1;           // [in] Toward the incoming ray
  public float3 k2;           // [in] Toward the sampled light
  public float3 xi;           // [in] 3 random [0..1]
  public float3 bsdf_diffuse; // [out] Diffuse contribution
  public float3 bsdf_glossy;  // [out] Specular contribution
  public float pdf;           // [out] PDF
};

/** @DOC_START
# struct `BsdfSampleData`
> Data structure for sampling a BSDF. See the file for parameter documentation.
@DOC_END  */
public struct BsdfSampleData {
  public float3 k1;            // [in] Toward the incoming ray
  public float3 k2;            // [out] Toward the sampled light
  public float3 xi;            // [in] 3 random [0..1]
  public float pdf;            // [out] PDF
  public float3 bsdf_over_pdf; // [out] contribution / PDF
  public int event_type;       // [out] one of the event above
};
