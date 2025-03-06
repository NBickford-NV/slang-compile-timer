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

#pragma once

#include "dh_scn_desc.hlsli"

// NOTE(nbickford): This code currently assumes indices point directly to
// descriptors in the descriptor heap, and that a value of ~0U is used for
// null values instead of 0.

static const uint NULL_INDEX = ~0U;

uint3 getTriangleIndices(RenderPrimitive renderPrim, uint idx)
{
    StructuredBuffer<uint3> indexBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.indexDescIdx)];
    return indexBuffer[idx];
}

float3 getVertexPosition(RenderPrimitive renderPrim, uint idx)
{
    StructuredBuffer<float3> positionBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.positionDescIdx)];
    return positionBuffer[idx];
}

float3 getInterpolatedVertexPosition(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics)
{
    StructuredBuffer<float3> positionBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.positionDescIdx)];
    float3 pos[3];
    pos[0] = positionBuffer[idx.x];
    pos[1] = positionBuffer[idx.y];
    pos[2] = positionBuffer[idx.z];
    return pos[0] * barycentrics.x + pos[1] * barycentrics.y + pos[2] * barycentrics.z;
}

bool hasVertexNormal(RenderPrimitive renderPrim)
{
    return renderPrim.vertexBuffer.normalDescIdx != NULL_INDEX;
}

float3 getVertexNormal(RenderPrimitive renderPrim, uint idx)
{
    if (!hasVertexNormal(renderPrim))
        return float3(0, 0, 1);
    StructuredBuffer<float3> normalBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.normalDescIdx)];
    return normalBuffer[idx];
}

float3 getInterpolatedVertexNormal(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics)
{
    if (!hasVertexNormal(renderPrim))
        return float3(0, 0, 1);
    StructuredBuffer<float3> normalBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.normalDescIdx)];
    float3 nrm[3];
    nrm[0] = normalBuffer[idx.x];
    nrm[1] = normalBuffer[idx.y];
    nrm[2] = normalBuffer[idx.z];
    return nrm[0] * barycentrics.x + nrm[1] * barycentrics.y + nrm[2] * barycentrics.z;
}

bool hasVertexTexCoord0(RenderPrimitive renderPrim)
{
    return renderPrim.vertexBuffer.texCoord0DescIdx != NULL_INDEX;
}

float2 getVertexTexCoord0(RenderPrimitive renderPrim, uint idx)
{
    if (!hasVertexTexCoord0(renderPrim))
        return float2(0, 0);
    StructuredBuffer<float2> texcoordBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.texCoord0DescIdx)];
    return texcoordBuffer[idx];
}

float2 getInterpolatedVertexTexCoord0(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics)
{
    if (!hasVertexTexCoord0(renderPrim))
        return float2(0, 0);
    StructuredBuffer<float2> texcoordBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.texCoord0DescIdx)];
    float2 uv[3];
    uv[0] = texcoordBuffer[idx.x];
    uv[1] = texcoordBuffer[idx.y];
    uv[2] = texcoordBuffer[idx.z];
    return uv[0] * barycentrics.x + uv[1] * barycentrics.y + uv[2] * barycentrics.z;
}

bool hasVertexTexCoord1(RenderPrimitive renderPrim)
{
    return renderPrim.vertexBuffer.texCoord1DescIdx != NULL_INDEX;
}

float2 getVertexTexCoord1(RenderPrimitive renderPrim, uint idx)
{
    if (!hasVertexTexCoord1(renderPrim))
        return float2(0, 0);
    StructuredBuffer<float2> texcoordBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.texCoord1DescIdx)];
    return texcoordBuffer[idx];
}

float2 getInterpolatedVertexTexCoord1(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics)
{
    if (!hasVertexTexCoord1(renderPrim))
        return float2(0, 0);
    StructuredBuffer<float2> texcoordBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.texCoord1DescIdx)];
    float2 uv[3];
    uv[0] = texcoordBuffer[idx.x];
    uv[1] = texcoordBuffer[idx.y];
    uv[2] = texcoordBuffer[idx.z];
    return uv[0] * barycentrics.x + uv[1] * barycentrics.y + uv[2] * barycentrics.z;
}

bool hasVertexTangent(RenderPrimitive renderPrim)
{
    return renderPrim.vertexBuffer.tangentDescIdx != NULL_INDEX;
}

float4 getVertexTangent(RenderPrimitive renderPrim, uint idx)
{
    if (!hasVertexTangent(renderPrim))
        return float4(1, 0, 0, 1);
    StructuredBuffer<float4> tangentBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.tangentDescIdx)];
    return tangentBuffer[idx];
}

float4 getInterpolatedVertexTangent(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics)
{
    if (!hasVertexTangent(renderPrim))
        return float4(1, 0, 0, 1);

    StructuredBuffer<float4> tangentBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.tangentDescIdx)];
    float4 tng[3];
    tng[0] = tangentBuffer[idx.x];
    tng[1] = tangentBuffer[idx.y];
    tng[2] = tangentBuffer[idx.z];
    return tng[0] * barycentrics.x + tng[1] * barycentrics.y + tng[2] * barycentrics.z;
}

bool hasVertexColor(RenderPrimitive renderPrim)
{
    return renderPrim.vertexBuffer.colorDescIdx != NULL_INDEX;
}

float4 unpackUnorm4x8(uint x)
{
    return float4(unpack_u8u32(x)) / 255.0f;
}

float4 getVertexColor(RenderPrimitive renderPrim, uint idx)
{
    if (!hasVertexColor(renderPrim))
        return float4(1, 1, 1, 1);
    StructuredBuffer<uint> colorBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.colorDescIdx)];
    return unpackUnorm4x8(colorBuffer[idx]);
}

float4 getInterpolatedVertexColor(RenderPrimitive renderPrim, uint3 idx, float3 barycentrics)
{
    if (!hasVertexColor(renderPrim))
        return float4(1, 1, 1, 1);

    StructuredBuffer<uint> colorBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(renderPrim.vertexBuffer.colorDescIdx)];
    float4 col[3];
    col[0] = unpackUnorm4x8(colorBuffer[idx.x]);
    col[1] = unpackUnorm4x8(colorBuffer[idx.y]);
    col[2] = unpackUnorm4x8(colorBuffer[idx.z]);
    return col[0] * barycentrics.x + col[1] * barycentrics.y + col[2] * barycentrics.z;
}
