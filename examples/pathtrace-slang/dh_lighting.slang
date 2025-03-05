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

module dh_lighting;

/* @DOC_START
Common structures used for lights other than environment lighting.
@DOC_END */

public const int eLightTypeNone = 0;
public const int eLightTypeDirectional = 1;
public const int eLightTypeSpot = 2;
public const int eLightTypePoint = 3;

//-----------------------------------------------------------------------
// Use for light/env contribution
public struct VisibilityContribution {
  public float3 radiance; // Radiance at the point if light is visible
  public float3 lightDir; // Direction to the light, to shoot shadow ray
  public float lightDist; // Distance to the light (1e32 for infinite or sky)
  public bool visible;    // true if in front of the face and should shoot shadow ray
};

public struct LightContrib {
  public float3 incidentVector;
  public float halfAngularSize;
  public float3 intensity;
  public float distance;
};

public struct Light {
  public float3 direction;
  public int type;

  public float3 position;
  public float radius;

  public float3 color;
  public float
      intensity; // illuminance (lm/m2) for directional lights, luminous intensity (lm/sr) for positional lights

  public float angularSizeOrInvRange; // angular size for directional lights, 1/range for spot and point lights
  public float innerAngle;
  public float outerAngle;
  int _pad;
};

// this isn't used in the Slang port, but is included here for now.
#ifdef __cplusplus
inline Light defaultLight() {
  Light l;
  l.position = vec3 { 5.0F, 5.F, 5.F };
  l.direction = glm::normalize(vec3 { 0.0F, -.7F, -.7F });
  l.type = eLightTypeDirectional;
  l.angularSizeOrInvRange = glm::radians(0.53F);
  l.color = { 1.0F, 1.0F, 1.0F };
  l.intensity = 0.F; // Dark
  l.innerAngle = glm::radians(10.F);
  l.outerAngle = glm::radians(30.F);
  l.radius = 1.0F;

  return l;
}
#endif //__cplusplus
