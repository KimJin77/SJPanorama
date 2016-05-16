attribute vec4 position;
attribute vec2 texcoord;

varying vec2 v_texcoord;

uniform mat4 modelViewProjectionMatrix;

void main() {
  v_texcoord = texcoord;
  gl_Position = modelViewProjectionMatrix * position;
}
