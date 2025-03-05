/*
 * Copyright (c) 2023-2024, NVIDIA CORPORATION.  All rights reserved.
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
 * SPDX-FileCopyrightText: Copyright (c) 2023-2024, NVIDIA CORPORATION.
 * SPDX-License-Identifier: Apache-2.0
 */

/* @DOC_START
Included in shaders to provide access to vertex data, so long as vertex
data follows a standard form.

Includes `getTriangleIndices`, and `getVertex*` and `getInterpolatedVertex*`
functions for all attributes.
@DOC_END */

module vertex_accessor;

import dh_scn_desc;

public uint3 getTriangleIndices(RenderPrimitive renderPrim, uint idx) { return renderPrim.indexAddress[idx]; }

public float3 getVertexPosition(RenderPrimitive renderPrim, uint idx) {
  return renderPrim.vertexBuffer.positionAddress[idx];
}

public float3 getInterpolatedVertexPosition(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics) {
  float3 *positionBuffer = renderPrim.vertexBuffer.positionAddress;
  float3 pos[3];
  pos[0] = positionBuffer[idx.x];
  pos[1] = positionBuffer[idx.y];
  pos[2] = positionBuffer[idx.z];
  return pos[0] * barycentrics.x + pos[1] * barycentrics.y + pos[2] * barycentrics.z;
}

public bool hasVertexNormal(RenderPrimitive renderPrim) { return renderPrim.vertexBuffer.normalAddress != nullptr; }

public float3 getVertexNormal(RenderPrimitive renderPrim, uint idx) {
  if (!hasVertexNormal(renderPrim))
    return float3(0, 0, 1);
  return renderPrim.vertexBuffer.normalAddress[idx];
}

public float3 getInterpolatedVertexNormal(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics) {
  if (!hasVertexNormal(renderPrim))
    return float3(0, 0, 1);
  float3 *normalBuffer = renderPrim.vertexBuffer.normalAddress;
  float3 nrm[3];
  nrm[0] = normalBuffer[idx.x];
  nrm[1] = normalBuffer[idx.y];
  nrm[2] = normalBuffer[idx.z];
  return nrm[0] * barycentrics.x + nrm[1] * barycentrics.y + nrm[2] * barycentrics.z;
}

public bool hasVertexTexCoord0(RenderPrimitive renderPrim) {
  return renderPrim.vertexBuffer.texCoord0Address != nullptr;
}

public float2 getVertexTexCoord0(RenderPrimitive renderPrim, uint idx) {
  if (!hasVertexTexCoord0(renderPrim))
    return float2(0, 0);
  return renderPrim.vertexBuffer.texCoord0Address[idx];
}

public float2 getInterpolatedVertexTexCoord0(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics) {
  if (!hasVertexTexCoord0(renderPrim))
    return float2(0, 0);
  float2 *texcoordBuffer = renderPrim.vertexBuffer.texCoord0Address;
  float2 uv[3];
  uv[0] = texcoordBuffer[idx.x];
  uv[1] = texcoordBuffer[idx.y];
  uv[2] = texcoordBuffer[idx.z];
  return uv[0] * barycentrics.x + uv[1] * barycentrics.y + uv[2] * barycentrics.z;
}

public bool hasVertexTexCoord1(RenderPrimitive renderPrim) {
  return renderPrim.vertexBuffer.texCoord1Address != nullptr;
}

public float2 getVertexTexCoord1(RenderPrimitive renderPrim, uint idx) {
  if (!hasVertexTexCoord1(renderPrim))
    return float2(0, 0);
  return renderPrim.vertexBuffer.texCoord1Address[idx];
}

public float2 getInterpolatedVertexTexCoord1(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics) {
  if (!hasVertexTexCoord1(renderPrim))
    return float2(0, 0);
  float2 *texcoordBuffer = renderPrim.vertexBuffer.texCoord1Address;
  float2 uv[3];
  uv[0] = texcoordBuffer[idx.x];
  uv[1] = texcoordBuffer[idx.y];
  uv[2] = texcoordBuffer[idx.z];
  return uv[0] * barycentrics.x + uv[1] * barycentrics.y + uv[2] * barycentrics.z;
}

public bool hasVertexTangent(RenderPrimitive renderPrim) { return renderPrim.vertexBuffer.tangentAddress != nullptr; }

public float4 getVertexTangent(RenderPrimitive renderPrim, uint idx) {
  if (!hasVertexTangent(renderPrim))
    return float4(1, 0, 0, 1);
  return renderPrim.vertexBuffer.tangentAddress[idx];
}

public float4 getInterpolatedVertexTangent(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics) {
  if (!hasVertexTangent(renderPrim))
    return float4(1, 0, 0, 1);

  float4 *tangentBuffer = renderPrim.vertexBuffer.tangentAddress;
  float4 tng[3];
  tng[0] = tangentBuffer[idx.x];
  tng[1] = tangentBuffer[idx.y];
  tng[2] = tangentBuffer[idx.z];
  return tng[0] * barycentrics.x + tng[1] * barycentrics.y + tng[2] * barycentrics.z;
}

public bool hasVertexColor(RenderPrimitive renderPrim) { return renderPrim.vertexBuffer.colorAddress != nullptr; }

public float4 unpackUnorm4x8(uint8_t4_packed x) { return float4(unpack_u8u32(x)) / 255.0f; }

public float4 getVertexColor(RenderPrimitive renderPrim, uint idx) {
  if (!hasVertexColor(renderPrim))
    return float4(1, 1, 1, 1);
  return unpackUnorm4x8(renderPrim.vertexBuffer.colorAddress[idx]);
}

public float4 getInterpolatedVertexColor(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics) {
  if (!hasVertexColor(renderPrim))
    return float4(1, 1, 1, 1);

  uint8_t4_packed *colorBuffer = renderPrim.vertexBuffer.colorAddress;
  float4 col[3];
  col[0] = unpackUnorm4x8(colorBuffer[idx.x]);
  col[1] = unpackUnorm4x8(colorBuffer[idx.y]);
  col[2] = unpackUnorm4x8(colorBuffer[idx.z]);
  return col[0] * barycentrics.x + col[1] * barycentrics.y + col[2] * barycentrics.z;
}
