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

#include "bsdf_functions.hlsli"
#include "bsdf_structs.hlsli"
#include "constants.hlsli"
#include "device_host.hlsli"
#include "dh_bindings.hlsli"
#include "dh_lighting.hlsli"
#include "dh_scn_desc.hlsli"
#include "dh_sky.hlsli"
#include "func.hlsli"
#include "ggx.hlsli"
#include "light_contrib.hlsli"
#include "pbr_mat_struct.hlsli"
#include "random.hlsli"
#include "ray_util.hlsli"
#include "vertex_accessor.hlsli"

[[vk::binding(B_tlas)]]
RaytracingAccelerationStructure topLevelAS;

[[vk::binding(B_outImage)]]
RWTexture2D<float4> image;

[[vk::binding(B_cameraInfo)]]
ConstantBuffer<CameraInfo> cameraInfo;

[[vk::binding(B_sceneDesc)]]
ConstantBuffer<SceneDescription> sceneDesc;

[[vk::binding(B_skyParam)]]
ConstantBuffer<PhysicalSkyParameters> skyInfo;

#include "pbr_mat_eval.hlsli"

[[vk::push_constant]]
ConstantBuffer<PushConstant> pushConst;

struct Ray
{
  float3 origin;
  float3 direction;
};

// Hit state information
struct HitState
{
  float3 pos;
  float3 nrm;
  float3 geonrm;
  float2 uv[2];
  float3 tangent;
  float3 bitangent;
  float4 color;
};

// Payload for the path tracer
struct HitPayload
{
  float    hitT;
  int      rnodeID;
  int      rprimID;
  HitState hitState;
};

//-----------------------------------------------------------------------
// Return hit information: position, normal, geonormal, uv, tangent, bitangent
HitState getHitState(RenderPrimitive renderPrim, float2 barycentricCoords, float3x4 worldToObject, float3x4 objectToWorld, int triangleID, float3 worldRayDirection)
{
  HitState hit;

  // Barycentric coordinate on the triangle
  const float3 barycentrics =
      float3(1.0 - barycentricCoords.x - barycentricCoords.y, barycentricCoords.x, barycentricCoords.y);

  // Getting the 3 indices of the triangle (local)
  uint3 triangleIndex = getTriangleIndices(renderPrim, triangleID);

  // Position
  float3 pos[3];
  pos[0]                = getVertexPosition(renderPrim, triangleIndex.x);
  pos[1]                = getVertexPosition(renderPrim, triangleIndex.y);
  pos[2]                = getVertexPosition(renderPrim, triangleIndex.z);
  const float3 position = mixBary(pos[0], pos[1], pos[2], barycentrics);
  hit.pos               = mul(objectToWorld, float4(position, 1.0));

  // Normal
  const float3 geoNormal      = normalize(cross(pos[1] - pos[0], pos[2] - pos[0]));
  float3       worldGeoNormal = normalize(mul(geoNormal, worldToObject).xyz);
  float3       normal         = geoNormal;
  if(hasVertexNormal(renderPrim))
    normal = getInterpolatedVertexNormal(renderPrim, triangleIndex, barycentrics);
  float3 worldNormal = normalize(mul(normal, worldToObject).xyz);
  hit.geonrm         = worldGeoNormal;
  hit.nrm            = worldNormal;

  // Color
  hit.color = getInterpolatedVertexColor(renderPrim, triangleIndex, barycentrics);

  // TexCoord
  hit.uv[0] = getInterpolatedVertexTexCoord0(renderPrim, triangleIndex, barycentrics);
  hit.uv[1] = getInterpolatedVertexTexCoord1(renderPrim, triangleIndex, barycentrics);

  // Tangent - Bitangent
  float4 tng[3];
  if(hasVertexTangent(renderPrim))
  {
    tng[0] = getVertexTangent(renderPrim, triangleIndex.x);
    tng[1] = getVertexTangent(renderPrim, triangleIndex.y);
    tng[2] = getVertexTangent(renderPrim, triangleIndex.z);
  }
  else
  {
    float4 t = makeFastTangent(normal);
    tng[0]   = t;
    tng[1]   = t;
    tng[2]   = t;
  }

  hit.tangent   = normalize(mixBary(tng[0].xyz, tng[1].xyz, tng[2].xyz, barycentrics));
  hit.tangent   = mul(objectToWorld, float4(hit.tangent, 0.0));
  hit.tangent   = normalize(hit.tangent - hit.nrm * dot(hit.nrm, hit.tangent));
  hit.bitangent = cross(hit.nrm, hit.tangent) * tng[0].w;

  // Adjusting normal
  const float3 V = (-worldRayDirection);
  if(dot(hit.geonrm, V) < 0)  // Flip if back facing
    hit.geonrm = -hit.geonrm;

  // If backface
  if(dot(hit.geonrm, hit.nrm) < 0)  // Make Normal and GeoNormal on the same side
  {
    hit.nrm       = -hit.nrm;
    hit.tangent   = -hit.tangent;
    hit.bitangent = -hit.bitangent;
  }

  // handle low tessellated meshes with smooth normals
  float3 k2 = reflect(-V, hit.nrm);
  if(dot(hit.geonrm, k2) < 0.0F)
    hit.nrm = hit.geonrm;

  // For low tessalated, avoid internal reflection
  float3 r = reflect(normalize(worldRayDirection), hit.nrm);
  if(dot(r, hit.geonrm) < 0)
    hit.nrm = hit.geonrm;

  return hit;
}

struct DirectLight
{
  float3 direction;        // Direction to the light
  float3 radianceOverPdf;  // Radiance over pdf
  float  distance;         // Distance to the light
  float  pdf;              // Probability of sampling this light
};

//-----------------------------------------------------------------------
// This should sample any lights in the scene, but we only have the sun
void sampleLights(float3 pos, float3 normal, float3 worldRayDirection, inout uint seed, out DirectLight directLight)
{
  float2            randVal   = float2(rand(seed), rand(seed));
  SkySamplingResult skySample = samplePhysicalSky(skyInfo, randVal);

  directLight.direction       = skySample.direction;
  directLight.pdf             = skySample.pdf;
  directLight.distance        = INFINITE;
  directLight.radianceOverPdf = skySample.radiance / skySample.pdf;
}

//----------------------------------------------------------
// Testing if the hit is opaque or alpha-transparent
// Return true if it is opaque
template<typename rayQueryWithFlags>
bool hitTest(rayQueryWithFlags rayQuery, inout uint seed)
{
  int rnodeID    = rayQuery.CandidateInstanceID();
  int rprimID    = rayQuery.CandidateInstanceIndex();
  int triangleID = rayQuery.CandidatePrimitiveIndex();

  // Retrieve the Primitive mesh buffer information
  StructuredBuffer<RenderNode>      renderNodeBuffer      = ResourceDescriptorHeap[sceneDesc.renderNodeDescIdx];
  RenderNode                        renderNode            = renderNodeBuffer[rnodeID];
  StructuredBuffer<RenderPrimitive> renderPrimitiveBuffer = ResourceDescriptorHeap[sceneDesc.renderPrimitiveDescIdx];
  RenderPrimitive                   renderPrim            = renderPrimitiveBuffer[rprimID];

  // Find the material of the primitive
  const uint matIndex = max(0, renderNode.materialID);  // material of primitive mesh
  StructuredBuffer<GltfShadeMaterial> materialBuffer = ResourceDescriptorHeap[sceneDesc.materialDescIdx];  // Buffer of materials
  GltfShadeMaterial material = materialBuffer[matIndex];
  if(material.alphaMode == ALPHA_OPAQUE)
    return true;

  float baseColorAlpha = material.pbrBaseColorFactor.a;
  if(isTexturePresent(material.pbrBaseColorTexture))
  {
    // Getting the 3 indices of the triangle (local)
    uint3 triangleIndex = getTriangleIndices(renderPrim, triangleID);  //

    // Get the texture coordinate
    float2       bary         = rayQuery.CandidateTriangleBarycentrics();
    const float3 barycentrics = float3(1.0 - bary.x - bary.y, bary.x, bary.y);
    float2 tc[2];
    tc[0] = getInterpolatedVertexTexCoord0(renderPrim, triangleIndex, barycentrics);
    tc[1] = getInterpolatedVertexTexCoord1(renderPrim, triangleIndex, barycentrics);

    GltfTextureInfo tinfo    = material.pbrBaseColorTexture;
    float2          texCoord = float2(mul(float3(tc[tinfo.texCoord], 1), tinfo.uvTransform));

    Texture2D    texture      = ResourceDescriptorHeap[NonUniformResourceIndex(tinfo.index)];
    SamplerState samplerState = SamplerDescriptorHeap[NonUniformResourceIndex(tinfo.index)];
    baseColorAlpha *= texture.SampleLevel(samplerState, texCoord, 0).a;
  }

  float opacity;
  if(material.alphaMode == ALPHA_MASK)
  {
    opacity = baseColorAlpha > material.alphaCutoff ? 1.0 : 0.0;
  }
  else
  {
    opacity = baseColorAlpha;
  }

  // do alpha blending the stochastically way
  if(rand(seed) > opacity)
    return false;

  return true;
}

//-----------------------------------------------------------------------
// Shoot a ray an return the information of the closest hit, in the
// PtPayload structure (PRD)
//
void traceRay(Ray ray, inout HitPayload payload, inout uint seed)
{
  payload.hitT = INFINITE;  // Default when not hitting anything

  // NOTE(nbickford): Is this correct?
  RayQuery<RAY_FLAG_CULL_BACK_FACING_TRIANGLES> rayQuery;

  RayDesc rayDesc;
  rayDesc.Origin = ray.origin;
  rayDesc.TMin   = 0.0f;
  rayDesc.TMax   = INFINITE;
  rayQuery.TraceRayInline(topLevelAS, rayQuery.RayFlags(), 0xFF, rayDesc);

  while(rayQuery.Proceed())
  {
    if(hitTest(rayQuery, seed))
    {
      rayQuery.CommitNonOpaqueTriangleHit();
    }
  }

  if(rayQuery.CommittedStatus() != COMMITTED_NOTHING)
  {
    float2   barycentricCoords = rayQuery.CommittedTriangleBarycentrics();
    int      rnodeID           = rayQuery.CommittedInstanceID();
    int      rprimID           = rayQuery.CommittedInstanceIndex();
    int      triangleID        = rayQuery.CommittedPrimitiveIndex();
    float3x4 worldToObject     = rayQuery.CommittedWorldToObject3x4();  // NOTE(nbickford): Hopefully this is correct
    float3x4 objectToWorld     = rayQuery.CommittedObjectToWorld3x4();
    float    hitT              = rayQuery.CommittedRayT();
    float3   worldRayDirection = rayQuery.WorldRayDirection();

    // Retrieve the Primitive mesh buffer information
    StructuredBuffer<RenderPrimitive> renderPrimitiveBuffer = ResourceDescriptorHeap[sceneDesc.renderPrimitiveDescIdx];
    RenderPrimitive                   renderPrim            = renderPrimitiveBuffer[rprimID];

    HitState hit = getHitState(renderPrim, barycentricCoords, worldToObject, objectToWorld, triangleID, worldRayDirection);

    payload.hitT     = hitT;
    payload.rnodeID  = rnodeID;
    payload.rprimID  = rprimID;
    payload.hitState = hit;
  }
}

//-----------------------------------------------------------------------
// Shadow ray - return true if a ray hits anything
//
//
bool traceShadow(Ray ray, float maxDist, inout uint seed)
{
  // gl_RayFlagsOpaqueEXT | gl_RayFlagsTerminateOnFirstHitEXT;
  RayQuery<RAY_FLAG_CULL_BACK_FACING_TRIANGLES> rayQuery;

  RayDesc rayDesc;
  rayDesc.Origin    = ray.origin;
  rayDesc.TMin      = 0.0f;
  rayDesc.Direction = ray.direction;
  rayDesc.TMax      = maxDist;
  rayQuery.TraceRayInline(topLevelAS, rayQuery.RayFlags(), 0xFF, rayDesc);

  while(rayQuery.Proceed())
  {
    if(hitTest(rayQuery, seed))
    {
      rayQuery.CommitNonOpaqueTriangleHit();
    }
  }

  return (rayQuery.CommittedStatus() != COMMITTED_NOTHING);  // Is Hit ?
}

//-----------------------------------------------------------------------
//-----------------------------------------------------------------------
float3 pathTrace(Ray ray, inout uint seed)
{
  float3 radiance   = 0.0F.rrr;
  float3 throughput = 1.0F.rrr;
  bool   isInside   = false;

  // Setting up the material
  StructuredBuffer<GltfShadeMaterial> materials = ResourceDescriptorHeap[sceneDesc.materialDescIdx];  // Buffer of materials
  StructuredBuffer<RenderNode> renderNodes = ResourceDescriptorHeap[sceneDesc.renderNodeDescIdx];  // Buffer of instances
  StructuredBuffer<RenderPrimitive> renderPrims = ResourceDescriptorHeap[sceneDesc.renderPrimitiveDescIdx];  // Buffer of meshes

  HitPayload payload;

  for(int depth = 0; depth < pushConst.maxDepth; depth++)
  {
    traceRay(ray, payload, seed);

    // Hitting the environment, then exit
    if(payload.hitT == INFINITE)
    {
      float3 sky_color = evalPhysicalSky(skyInfo, ray.direction);
      return radiance + (sky_color * throughput);
    }

    // Getting the hit information (primitive/mesh that was hit)
    HitState hit = payload.hitState;

    // Setting up the material
    RenderPrimitive   renderPrim    = renderPrims[payload.rprimID];   // Primitive information
    RenderNode        renderNode    = renderNodes[payload.rnodeID];   // Node information
    int               materialIndex = max(0, renderNode.materialID);  // Material ID of hit mesh
    GltfShadeMaterial material      = materials[materialIndex];       // Material of the hit object

    material.pbrBaseColorFactor *= hit.color;  // Modulate the base color with the vertex color

    MeshState   mesh = { hit.nrm, hit.tangent, hit.bitangent, hit.geonrm, hit.uv, isInside };
    PbrMaterial pbrMat = evaluateMaterial(material, mesh);

    // Adding emissive
    radiance += pbrMat.emissive * throughput;

    // Apply volume attenuation
    bool thin_walled = pbrMat.isThinWalled;
    if(isInside && !thin_walled)
    {
      const float3 abs_coeff = absorptionCoefficient(pbrMat);
      throughput.x *= abs_coeff.x > 0.0 ? exp(-abs_coeff.x * payload.hitT) : 1.0;
      throughput.y *= abs_coeff.y > 0.0 ? exp(-abs_coeff.y * payload.hitT) : 1.0;
      throughput.z *= abs_coeff.z > 0.0 ? exp(-abs_coeff.z * payload.hitT) : 1.0;
    }

    float3 contribution = float3(0, 0, 0);  // Direct lighting contribution

    // Light contribution; can be environment or punctual lights
    DirectLight directLight;
    sampleLights(hit.pos, pbrMat.N, ray.direction, seed, directLight);

    // Evaluation of direct light (sun)
    const bool nextEventValid = ((dot(directLight.direction, hit.geonrm) > 0.0F) != isInside) && directLight.pdf != 0.0F;
    if(nextEventValid)
    {
      BsdfEvaluateData evalData;
      evalData.k1 = -ray.direction;
      evalData.k2 = directLight.direction;
      evalData.xi = float3(rand(seed), rand(seed), rand(seed));
      bsdfEvaluate(evalData, pbrMat);

      if(evalData.pdf > 0.0)
      {
        const float mis_weight = (directLight.pdf == DIRAC) ? 1.0F : directLight.pdf / (directLight.pdf + evalData.pdf);

        // sample weight
        const float3 w = throughput * directLight.radianceOverPdf * mis_weight;
        contribution += w * evalData.bsdf_diffuse;
        contribution += w * evalData.bsdf_glossy;
      }
    }

    // Sample BSDF
    {
      BsdfSampleData sampleData;
      sampleData.k1 = -ray.direction;  // outgoing direction
      sampleData.xi = float3(rand(seed), rand(seed), rand(seed));
      bsdfSample(sampleData, pbrMat);

      throughput *= sampleData.bsdf_over_pdf;
      ray.direction = sampleData.k2;

      if(sampleData.event_type == BSDF_EVENT_ABSORB)
      {
        break;  // Need to add the contribution ?
      }
      else
      {
        // Continue path
        bool isSpecular     = (sampleData.event_type & BSDF_EVENT_IMPULSE) != 0;
        bool isTransmission = (sampleData.event_type & BSDF_EVENT_TRANSMISSION) != 0;

        float3 offsetDir = dot(ray.direction, hit.geonrm) > 0 ? hit.geonrm : -hit.geonrm;
        ray.origin       = offsetRay(hit.pos, offsetDir);

        if(isTransmission)
        {
          isInside = !isInside;
        }
      }
    }

    // We are adding the contribution to the radiance only if the ray is not occluded by an object.
    if(nextEventValid)
    {
      Ray  shadowRay = {ray.origin, directLight.direction};
      bool inShadow  = traceShadow(shadowRay, directLight.distance, seed);
      if(!inShadow)
      {
        radiance += contribution;
      }
    }

    // Russian-Roulette (minimizing live state)
    float rrPcont = min(max(throughput.x, max(throughput.y, throughput.z)) + 0.001F, 0.95F);
    if(rand(seed) >= rrPcont)
      break;                // paths with low throughput that won't contribute
    throughput /= rrPcont;  // boost the energy of the non-terminated paths
  }

  return radiance;
}

//-----------------------------------------------------------------------
// Sampling the pixel
//-----------------------------------------------------------------------
float3 samplePixel(inout uint seed, uint2 launchID, uint2 launchSize)
{
  // Subpixel jitter: send the ray through a different position inside the pixel each time, to provide antialiasing.
  float2 subPixelJitter = float2(rand(seed), rand(seed));
  float2 clipCoords     = (float2(launchID) + subPixelJitter) / float2(launchSize) * 2.0 - 1.0;
  float4 viewCoords     = mul(cameraInfo.projInv, float4(clipCoords, -1.0, 1.0));
  viewCoords /= viewCoords.w;

  const float3 origin    = float3(cameraInfo.viewInv[3].xyz);
  const float3 direction = normalize(mul(cameraInfo.viewInv, viewCoords).xyz - origin);

  Ray ray = { origin.xyz, direction.xyz };

  float3 radiance = pathTrace(ray, seed);

  // Removing fireflies
  float lum = dot(radiance, float3(0.212671F, 0.715160F, 0.072169F));
  if(lum > pushConst.fireflyClampThreshold)
  {
    radiance *= pushConst.fireflyClampThreshold / lum;
  }

  return radiance;
}

//-----------------------------------------------------------------------
// Main function
//-----------------------------------------------------------------------
[shader("compute")][numthreads(16, 16, 1)] void main(uint3 launchID
                                                     : SV_DispatchThreadID) {
  uint2 launchSize;
  image.GetDimensions(launchSize.x, launchSize.y);

  // Check if not outside boundaries
  if(launchID.x >= launchSize.x || launchID.y >= launchSize.y)
    return;

  // Initialize the random number
  uint seed = xxhash32(uint3(launchID.xy, pushConst.frame));

  // Sampling n times the pixel
  float3 pixel_color = float3(0.0F, 0.0F, 0.0F);
  for(int s = 0; s < pushConst.maxSamples; s++)
  {
    pixel_color += samplePixel(seed, launchID.xy, launchSize);
  }
  pixel_color /= pushConst.maxSamples;

  bool firstFrame = (pushConst.frame <= 1);
  // Saving result
  if(firstFrame)
  {  // First frame, replace the value in the buffer
    image[launchID.xy] = float4(pixel_color, 1.0F);
  }
  else
  {  // Do accumulation over time
    float  a         = 1.0F / float(pushConst.frame + 1);
    float3 old_color = image[launchID.xy].xyz;
    image[launchID.xy] = float4(lerp(old_color, pixel_color, a), 1.0F);
  }
}
