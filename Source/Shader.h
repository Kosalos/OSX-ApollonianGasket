#pragma once
#include <simd/simd.h>

typedef struct {
    matrix_float4x4 transformMatrix;
    matrix_float3x3 endPosition;
} ArcBallData;

typedef struct {
    float ambient;
    float diffuse;
    float specular;
    float harshness;
    float saturation;
    float gamma;
    float shadowMin;
    float shadowMax;
    float shadowMult;
    float shadowAmt;
} Lighting;

typedef struct {
    int version;
    vector_float3 camera;
    vector_float3 focus;
    vector_float3 light;
    vector_float3 color;
    int xSize,ySize;
    float minDist;
    float zoom;
    float parallax;
    float multiplier;
    float dali;
    
    ArcBallData aData;
    Lighting lighting;

    vector_float3 viewVector,topVector,sideVector;

    float foam;
    float foam2;
    float fog;
    float bend;
    
    int txtOnOff;
    vector_float2 txtSize;
    vector_float3 txtCenter;
} Control;
