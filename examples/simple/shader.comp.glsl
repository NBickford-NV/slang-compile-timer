#version 460
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PushConstantCompute
{
  uint64_t bufferAddress;
  uint     numVertices;
};

layout(push_constant, scalar) uniform PushConsts
{
  PushConstantCompute pushConst;
};

struct Vertex
{
  vec3 position;
};

layout(buffer_reference, scalar) buffer VertexBuffer
{
  Vertex data[];
};

void main()
{
  uint index = gl_GlobalInvocationID.x;

  if(index >= pushConst.numVertices)
    return;

  VertexBuffer vertices = VertexBuffer(pushConst.bufferAddress);

  float angle = (index + 1) * 2.3f;

  vec3 vertex = vertices.data[index].position;

  float cosAngle = cos(angle);
  float sinAngle = sin(angle);
  mat3 rotationMatrix = mat3(
    cosAngle, -sinAngle, 0.0,
    sinAngle,  cosAngle, 0.0,
         0.0,       0.0, 1.0
  );

  vec3 rotatedVertex = rotationMatrix * vertex;

  vertices.data[index].position = rotatedVertex;
}
