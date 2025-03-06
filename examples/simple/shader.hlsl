struct Vertex
{
  float3 position;
};

RWStructuredBuffer<Vertex> vertices;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 threadIdx : SV_DispatchThreadID)
{
  uint index = threadIdx.x;

  uint numVertices = 0;
  uint stride_unused = 0;
  vertices.GetDimensions(numVertices, stride_unused);
  if(index >= numVertices)
    return;

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
