struct PushConstantCompute
{
  uint64_t bufferAddress;
  uint     numVertices;
};

struct Vertex
{
  float3 position;
};

[[vk::push_constant]]
ConstantBuffer<PushConstantCompute> pushConst;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 threadIdx : SV_DispatchThreadID)
{
  uint index = threadIdx.x;

  if(index >= pushConst.numVertices)
    return;

  Vertex* vertices = (Vertex*)pushConst.bufferAddress;

  float angle = (index + 1) * 2.3f;

  float3 vertex = vertices[index].position;

  float cosAngle = cos(angle);
  float sinAngle = sin(angle);
  float3x3 rotationMatrix = float3x3(
    cosAngle, -sinAngle, 0.0,
    sinAngle,  cosAngle, 0.0,
         0.0,       0.0, 1.0
  );

  float3 rotatedVertex = mul(rotationMatrix, vertex);

  vertices[index].position = rotatedVertex;
}
