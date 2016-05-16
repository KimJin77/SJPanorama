//
//  ParanoramaViewController.m
//  SJPanorama
//
//  Created by Sim Jin on 16/5/10.
//  Copyright © 2016年 Sim Jin. All rights reserved.
//

#import "ParanoramaViewController.h"
#import "GLProgram.h"
#import <CoreMotion/CoreMotion.h>

#define MAX_OVERTURE 95.0
#define MIN_OVERTURE 25.0
#define DEFAULT_OVERTURE 85.0

// Uniform Index
enum {
  UNIFORM_MODELVIEWPROJECTION_MATRIX,
  UNIFORM_TEXTURE,
  NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

@interface ParanoramaViewController() {
  GLProgram *_glProgram;
  int _numIndices;
  GLuint _vertexBuffer;
  GLuint _textureBuffer;
  GLuint _indicesBuffer;
  GLKMatrix4 _modelViewProjectionMatrix;
  
  float _fingerRotationX;
  float _fingerRotationY;
  float _savedGyroRotationX;
  float _savedGyroRotationY;
  float _overture;
}

@property (nonatomic, strong) EAGLContext *context;
@property (nonatomic, strong) GLKView *leftView;
@property (nonatomic, strong) GLKView *rightView;
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) CMAttitude *referenceAttitude;

@property (strong, nonatomic) NSMutableArray *currentTouches;

@property (nonatomic, strong) UIView *bottomBarView;
@property (nonatomic, assign) BOOL isVRMode;
@property (nonatomic, assign, getter=isUsingMotion) BOOL useMotion;

@end

@implementation ParanoramaViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  _overture = DEFAULT_OVERTURE;
  self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
  
  
  
//  GLKView *view = (GLKView *)self.view;
//  view.context = self.context;
//  view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
//  GLKView *leftView = [[GLKView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width / 2, self.view.frame.size.height) context:self.context];
  self.leftView = [[GLKView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width / 2, self.view.frame.size.height) context:self.context];
  self.leftView.delegate = self;
  self.leftView.drawableDepthFormat = GLKViewDrawableDepthFormat24;
  [self.view addSubview:self.leftView];
  self.rightView = [[GLKView alloc] initWithFrame:CGRectMake(self.view.frame.size.width / 2, 0, self.view.frame.size.width / 2, self.view.frame.size.height) context:self.context];
  self.rightView.delegate = self;
  self.rightView.drawableDepthFormat = GLKViewDrawableDepthFormat24;
  [self.view addSubview:self.rightView];
  
  self.isVRMode = YES;
  self.useMotion = NO;
  [self setupBottomBar];
  [self setupGL];
//  [self startDeviceMotion];
}

- (void)setupBottomBar {
  self.bottomBarView = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - 64, self.view.frame.size.width, 64)];
  self.bottomBarView.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.6];
  [self.view addSubview:self.bottomBarView];
  
  UIButton *vrModeButton = [[UIButton alloc] initWithFrame:CGRectMake(20, 12, 100, 40)];
  [vrModeButton setTitle:@"VR Mode" forState:UIControlStateNormal];
  [vrModeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  [vrModeButton setTitleColor:[UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.6] forState:UIControlStateSelected];
  [vrModeButton addTarget:self action:@selector(displayInVRMode:) forControlEvents:UIControlEventTouchUpInside];
  vrModeButton.backgroundColor = [UIColor whiteColor];
  vrModeButton.selected = YES;
  vrModeButton.layer.cornerRadius = 3.0;
  [self.bottomBarView addSubview:vrModeButton];
  
  UIButton *motionButton = [[UIButton alloc] initWithFrame:CGRectMake(120, 12, 100, 40)];
  [motionButton setTitle:@"Use Motion" forState:UIControlStateNormal];
  [motionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  [motionButton setTitleColor:[UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.6] forState:UIControlStateSelected];
  [motionButton addTarget:self action:@selector(useMotion:) forControlEvents:UIControlEventTouchUpInside];
  motionButton.layer.cornerRadius = 3.0;
  [self.bottomBarView addSubview:motionButton];
}

- (void)setupGL {
  [EAGLContext setCurrentContext:self.context];
  [self buildProgram];
  
  GLfloat *vVertices = NULL;
  GLfloat *vTextCoord = NULL;
  GLushort *indices = NULL;
  int numVertices = 0;
  
  _numIndices = esGenSphere(200, 1.0, &vVertices, NULL, &vTextCoord, &indices, &numVertices);

  // Vertex
  glGenBuffers(1, &_vertexBuffer);
  glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
  glBufferData(GL_ARRAY_BUFFER, numVertices*3*sizeof(GLfloat), vVertices, GL_STATIC_DRAW);
  glEnableVertexAttribArray(GLKVertexAttribPosition);
  glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLfloat)*3, NULL);
  
  // Texture
  glGenBuffers(1, &_textureBuffer);
  glBindBuffer(GL_ARRAY_BUFFER, _textureBuffer);
  glBufferData(GL_ARRAY_BUFFER, numVertices*2*sizeof(GLfloat), vTextCoord, GL_DYNAMIC_DRAW);
  glEnableVertexAttribArray([_glProgram attributeIndex:@"texcoord"]);
  glVertexAttribPointer([_glProgram attributeIndex:@"texcoord"], 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat)*2, NULL);
  
  // Indice
  glGenBuffers(1, &_indicesBuffer);
  
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indicesBuffer);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, _numIndices*sizeof(GLushort), indices, GL_STATIC_DRAW);
  
  [_glProgram use];
  
  
  [self loadTexture];
  glUniform1i([_glProgram uniformIndex:@"s_texture"], 0);
}

- (void)loadTexture {

  CGImageRef spriteImage = [UIImage imageNamed:@"minack-panorama.jpg"].CGImage;
  
  size_t width = CGImageGetWidth(spriteImage);
  size_t height = CGImageGetHeight(spriteImage);
  GLubyte *spriteData = (GLubyte *)calloc(width*height*4, sizeof(GLubyte));
  CGContextRef spriteContext = CGBitmapContextCreate(spriteData, width, height, 8, width*4,
                                                   CGImageGetColorSpace(spriteImage), kCGImageAlphaPremultipliedLast);
  CGContextDrawImage(spriteContext, CGRectMake(0, 0, width, height), spriteImage);
//   CGContextDrawImage(spriteContext, CGRectMake(0, 0, 333.5, 375), spriteImage);
  
  CGContextRelease(spriteContext);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  GLuint texName;
  glGenTextures(1, &texName);
  glBindTexture(GL_TEXTURE_2D, texName);
  
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, spriteData);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glActiveTexture(GL_TEXTURE0);
}

- (void)buildProgram {
  
  _glProgram = [[GLProgram alloc] initWithVertexShaderFilename:@"Shader" fragmentShaderFilename:@"Shader"];
  [_glProgram addAttribute:@"position"];
  [_glProgram addAttribute:@"texcoord"];
  if (![_glProgram link]) {
    NSString *programLog = [_glProgram programLog];
    NSLog(@"Program link log: %@", programLog);
    NSString *fragmentLog = [_glProgram fragmentShaderLog];
    NSLog(@"Fragment shader compile log: %@", fragmentLog);
    NSString *vertexLog = [_glProgram vertexShaderLog];
    NSLog(@"Vertex shader compile log: %@", vertexLog);
    _glProgram = nil;
    NSAssert(NO, @"Falied to link HalfSpherical shaders");
  }
  
  uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [_glProgram uniformIndex:@"modelViewProjectionMatrix"];
  uniforms[UNIFORM_TEXTURE] = [_glProgram uniformIndex:@"s_texture"];
}

- (void)update {
  float aspect = fabs(self.view.bounds.size.width / self.view.bounds.size.height);
  GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(_overture), aspect, 0.1, 1000.f);
  projectionMatrix = GLKMatrix4Rotate(projectionMatrix, 3.14159265f, 1.0f, 0.0f, 0.0f);
  
  GLKMatrix4 modelViewMatrix = GLKMatrix4Identity;
  modelViewMatrix = GLKMatrix4Scale(modelViewMatrix, 100.0f, 100.0f, 100.0f);
  if (self.isUsingMotion) {
    CMDeviceMotion *d = _motionManager.deviceMotion;
    if (d) {
      CMAttitude *attitude = d.attitude;
      if (self.referenceAttitude) [attitude multiplyByInverseOfAttitude:self.referenceAttitude];
      else self.referenceAttitude = attitude;
      
      float cRoll = -fabs(attitude.roll);
      float cYaw = attitude.yaw;
      float cPitch = attitude.pitch;
      
      UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
      if (orientation == UIDeviceOrientationLandscapeRight ){
        cPitch = cPitch*-1; // correct depth when in landscape right
      }
      modelViewMatrix = GLKMatrix4RotateX(modelViewMatrix, cRoll); // Up/Down axis
      modelViewMatrix = GLKMatrix4RotateY(modelViewMatrix, cPitch);
      modelViewMatrix = GLKMatrix4RotateZ(modelViewMatrix, cYaw);
      
      modelViewMatrix = GLKMatrix4RotateX(modelViewMatrix, M_PI/2);
      
      modelViewMatrix = GLKMatrix4RotateX(modelViewMatrix, _fingerRotationX);
      modelViewMatrix = GLKMatrix4RotateY(modelViewMatrix, _fingerRotationY);
      
      _savedGyroRotationX = cRoll + M_PI/2 + _fingerRotationX;
      _savedGyroRotationY = cPitch + _fingerRotationY;
    }
  } else {
    modelViewMatrix = GLKMatrix4RotateX(modelViewMatrix, _fingerRotationX);
    modelViewMatrix = GLKMatrix4RotateY(modelViewMatrix, _fingerRotationY);
  }
  
  
  _modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
  [self.leftView display];
  [self.rightView display];
}

#pragma mark - GLKViewDelegate

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
  
//  glViewport(0, 0, 100, 100);
  
  glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, _modelViewProjectionMatrix.m);
  
  glClearColor(0.2f, 0.5f, 0.3f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  glDrawElements(GL_TRIANGLES, _numIndices, GL_UNSIGNED_SHORT, 0);
}

#pragma mark - Core Motion
- (void)startDeviceMotion {
  
  self.useMotion = NO;
  
  self.motionManager = [[CMMotionManager alloc] init];
  self.motionManager.accelerometerUpdateInterval = 1/60.f;
  self.motionManager.gyroUpdateInterval = 1/60.f;
  self.motionManager.showsDeviceMovementDisplay = YES;
  self.referenceAttitude = self.motionManager.deviceMotion.attitude;
  
  _savedGyroRotationX = 0;
  _savedGyroRotationY = 0;
  
  [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryCorrectedZVertical];
  
  self.useMotion = YES;
}

- (void)stopDeviceMotion {
  _fingerRotationX = _savedGyroRotationX-_referenceAttitude.roll- M_PI_2;
  _fingerRotationY = _savedGyroRotationY;
  
  self.useMotion = NO;
  [_motionManager stopDeviceMotionUpdates];
  _motionManager = nil;
}

#pragma mark - Touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
  if(self.isUsingMotion) return;
  for (UITouch *touch in touches) {
    [_currentTouches addObject:touch];
  }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
  if(self.isUsingMotion) return;
  UITouch *touch = [touches anyObject];
  float distX = [touch locationInView:touch.view].x -
  [touch previousLocationInView:touch.view].x;
  float distY = [touch locationInView:touch.view].y -
  [touch previousLocationInView:touch.view].y;
  distX *= -0.005;
  distY *= -0.005;
  _fingerRotationX += distY *  _overture / 100;
  _fingerRotationY -= distX *  _overture / 100;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
  if (self.isUsingMotion) return;
  for (UITouch *touch in touches) {
    [_currentTouches removeObject:touch];
  }
}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
  for (UITouch *touch in touches) {
    [_currentTouches removeObject:touch];
  }
}

- (void)handlePinchGesture:(UIPinchGestureRecognizer *)recognizer {
  _overture /= recognizer.scale;
  
  if (_overture > MAX_OVERTURE)
    _overture = MAX_OVERTURE;
  if(_overture<MIN_OVERTURE)
    _overture = MIN_OVERTURE;
}

#pragma mark - Actions 
- (void)displayInVRMode:(UIButton *)sender {
  if (self.isVRMode) {
    self.leftView.frame = self.view.bounds;
    self.rightView.hidden = YES;
    sender.selected = NO;
    sender.backgroundColor = [UIColor clearColor];
  } else {
    self.leftView.frame = CGRectMake(0, 0, self.view.frame.size.width / 2, self.view.frame.size.height);
    self.rightView.hidden = NO;
    
  }
  self.isVRMode = !self.isVRMode;
}

- (void)useMotion:(UIButton *)sender {
  if (self.isUsingMotion) {
    sender.selected = NO;
    sender.backgroundColor = [UIColor clearColor];
    [self stopDeviceMotion];
  } else {
    sender.selected = YES;
    sender.backgroundColor = [UIColor whiteColor];
    [self startDeviceMotion];
  }
}

#pragma mark - Generate sphere

int esGenSphere(int numSlices, float radius, float** vertices, float** normals, float **texCoords, uint16_t** indices, int* numVertices_out) {
  int i, j;
  int numParallels = numSlices / 2;
  int numVertices = (numSlices + 1) * (numParallels + 1);
  int numIndices =  numParallels * numSlices * 6;
  float angleStep = (2.0 * M_PI) / ((float)numSlices);
  
  if (vertices != NULL) *vertices = malloc(sizeof(float) * 3 * numVertices);
  if (texCoords != NULL) *texCoords = malloc(sizeof(float) * 2 * numVertices);
  if (indices != NULL) *indices = malloc(sizeof(uint16_t) * numIndices);
  
  for (i = 0; i < numParallels+1; i++) {
    for (j = 0; j < numSlices+1; j++) {
      int vertex = (i * (numSlices + 1) + j) * 3;
      
      if (vertices) {
        (*vertices)[vertex + 0] = radius * sinf(angleStep * (float)i) * sinf(angleStep * (float)j);
        (*vertices)[vertex + 1] = radius * cosf(angleStep * (float)i);
        (*vertices)[vertex + 2] = radius * sinf(angleStep * (float)i) * cosf(angleStep * (float)j);
      }
      
      if (texCoords) {
        int texIndex = (i * (numSlices + 1) + j) * 2;
        (*texCoords)[texIndex + 0] = (float)j/(float)numSlices;
        (*texCoords)[texIndex + 1] = 1.0 - ((float)i / (float)(numParallels));
      }
    }
  }
  
  // Generate the indice
  if (indices != NULL) {
    uint16_t *indexBuf = (*indices);
    for (int i = 0; i < numParallels; i++) {
      for (int j = 0; j < numSlices; j++) {
        *indexBuf++ = i * (numSlices + 1) + j;
        *indexBuf++ = (i + 1) * (numSlices + 1) + j;
        *indexBuf++ = (i + 1) * (numSlices + 1) + (j + 1);
        
        *indexBuf++ = i * (numSlices + 1) + j;
        *indexBuf++ = (i + 1) * (numSlices + 1) + (j + 1);
        *indexBuf++ = i * (numSlices + 1) + (j + 1);
      }
    }
  }
  
  if (numVertices_out) *numVertices_out = numVertices;
  return numIndices;
}

@end
