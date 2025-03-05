/*
 * Copyright (c) 2022-2024, NVIDIA CORPORATION.  All rights reserved.
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
 * SPDX-FileCopyrightText: Copyright (c) 2022-2024, NVIDIA CORPORATION.
 * SPDX-License-Identifier: Apache-2.0
 */

module func;

/* @DOC_START
Useful utility functions for shaders.
@DOC_END */

import constants;

public float square(float x)
{
  return x * x;
}

/* @DOC_START
# Function `luminance`
> Returns the luminance of a linear RGB color, using Rec. 709 coefficients.
@DOC_END */
public float luminance(float3 color)
{
  return color.x * 0.2126F + color.y * 0.7152F + color.z * 0.0722F;
}

/* @DOC_START
# Function `clampedDot`
> Takes the dot product of two values and clamps the result to [0,1].
@DOC_END */
public float clampedDot(float3 x, float3 y)
{
  return clamp(dot(x, y), 0.0F, 1.0F);
}

/* @DOC_START
# Function `orthonormalBasis`
> Builds an orthonormal basis: given only a normal vector, returns a
tangent and bitangent.

This uses the technique from "Improved accuracy when building an orthonormal
basis" by Nelson Max, https://jcgt.org/published/0006/01/02.

Any tangent-generating algorithm must produce at least one discontinuity
when operating on a sphere (due to the hairy ball theorem); this has a
small ring-shaped discontinuity at `normal.z == -0.99998796`.
@DOC_END */
public void orthonormalBasis(float3 normal, out float3 tangent, out float3 bitangent)
{
  if(normal.z < -0.99998796F)  // Handle the singularity
  {
    tangent = float3(0.0F, -1.0F, 0.0F);
    bitangent = float3(-1.0F, 0.0F, 0.0F);
    return;
  }
  float a   = 1.0F / (1.0F + normal.z);
  float b   = -normal.x * normal.y * a;
  tangent   = float3(1.0F - normal.x * normal.x * a, b, -normal.x);
  bitangent = float3(b, 1.0f - normal.y * normal.y * a, -normal.y);
}

/* @DOC_START
# Function `makeFastTangent`
> Like `orthonormalBasis()`, but returns a tangent and tangent sign that matches
> the glTF convention.
@DOC_END */
public float4 makeFastTangent(float3 normal)
{
  float3 tangent, unused;
  orthonormalBasis(normal, tangent, unused);
  // The glTF bitangent sign here is 1.f since for
  // normal == vec3(0.0F, 0.0F, 1.0F), we get
  // tangent == vec3(1.0F, 0.0F, 0.0F) and bitangent == vec3(0.0F, 1.0F, 0.0F),
  // so bitangent = cross(normal, tangent).
  return float4(tangent, 1.f);
}

/* @DOC_START
# Function `rotate`
> Rotates the vector `v` around the unit direction `k` by an angle of `theta`.

At `theta == pi/2`, returns `cross(k, v) + k * dot(k, v)`. This means that
rotations are clockwise in right-handed coordinate systems and
counter-clockwise in left-handed coordinate systems.
@DOC_END */
public float3 rotate(float3 v, float3 k, float theta)
{
  float cos_theta = cos(theta);
  float sin_theta = sin(theta);

  return (v * cos_theta) + (cross(k, v) * sin_theta) + (k * dot(k, v)) * (1.0F - cos_theta);
}

/* @DOC_START
# Function `getSphericalUv`
> Given a direction, returns the UV coordinate of an environment map for that
> direction using a spherical projection.
@DOC_END */
public float2 getSphericalUv(float3 v)
{
  float gamma = asin(-v.y);
  float theta = atan2(v.z, v.x);

  float2 uv = float2(theta * M_1_OVER_PI * 0.5F, gamma * M_1_OVER_PI) + 0.5F;
  return uv;
}

/* @DOC_START
# Function `mixBary`
> Interpolates between 3 values, using the barycentric coordinates of a triangle.
@DOC_END */
public float2 mixBary(float2 a, float2 b, float2 c, float3 bary)
{
  return a * bary.x + b * bary.y + c * bary.z;
}

public float3 mixBary(float3 a, float3 b, float3 c, float3 bary)
{
  return a * bary.x + b * bary.y + c * bary.z;
}

public float4 mixBary(float4 a, float4 b, float4 c, float3 bary)
{
  return a * bary.x + b * bary.y + c * bary.z;
}

/* @DOC_START
# Function `cosineSampleHemisphere
> Samples a hemisphere using a cosine-weighted distribution.

See https://www.realtimerendering.com/raytracinggems/unofficial_RayTracingGems_v1.4.pdf,
section 16.6.1, "COSINE-WEIGHTED HEMISPHERE ORIENTED TO THE Z-AXIS".
@DOC_END */
public float3 cosineSampleHemisphere(float r1, float r2)
{
  float  r   = sqrt(r1);
  float  phi = M_TWO_PI * r2;
  float3 dir;
  dir.x = r * cos(phi);
  dir.y = r * sin(phi);
  dir.z = sqrt(1.F - r1);
  return dir;
}

/* @DOC_START
# Function `powerHeuristic`
> The power heuristic for multiple importance sampling, with `beta = 2`.

See equation 9.13 of https://graphics.stanford.edu/papers/veach_thesis/thesis.pdf.
@DOC_END */
public float powerHeuristic(float a, float b)
{
  const float t = a * a;
  return t / (b * b + t);
}

/* @DOC_START
# Function `sampleBlur`
> Samples a texture with a Gaussian blur kernel.
@DOC_END */
public float4 sampleBlur(Sampler2D texture, float2 uv, float lodLevel)
{
  // G(x, y) = (1 / (2 * pi * sigma^2)) * exp(-(x^2 + y^2) / (2 * sigma^2))
  // Gaussian blur kernel normalized
  const matrix<float, 3, 3> WEIGHTS_2D = { 0.0625, 0.125, 0.0625, 0.125, 0.25, 0.125, 0.0625, 0.125, 0.0625 };

  float2 resolution;
  float unused;
  texture.GetDimensions(uint(lodLevel), resolution.x, resolution.y, unused);
  float2 texelSize = 1.0 / resolution;

  float4 color = float4(0.0);
  [[ForceUnroll]]
  for (int i = 0; i < 3; i++) {
    [[ForceUnroll]]
    for (int j = 0; j < 3; j++) {
      float2 offsetUV = float2(i - 1, j - 1) * texelSize;
      color += texture.SampleLevel(uv + offsetUV, lodLevel) * WEIGHTS_2D[i][j];
    }
  }
  return color;
}

/* @DOC_START
# Function `smoothHDRBlur`
> Samples a texture with a Gaussian blur kernel, using multiple LOD levels.
* The blur amount controls the blending between the two LOD levels.
@DOC_END */
public float4 smoothHDRBlur(Sampler2D texture, float2 uv, float blurAmount)
{
  // Calculate the maximum LOD level
  float2 unused;
  float numLevels;
  texture.GetDimensions(0, unused.x, unused.y, numLevels);
  float maxLOD = numLevels - 1.0;

  // Calculate two adaptive LOD levels
  float lod0 = max(0, (maxLOD * blurAmount) - 2);
  float lod1 = maxLOD * blurAmount;

  // Sample multiple adaptive mip levels
  float4 color0 = sampleBlur(texture, uv, lod0);
  float4 color1 = sampleBlur(texture, uv, lod1);

  // Blend between two mip levels, each of which depend on `blurAmount`.
  float blurMix = 1.0 - pow(1.0 - blurAmount, 1.0 / 1.5);
  float4  blendedColor = lerp(color0, color1, 0.5);

  return blendedColor;
}
