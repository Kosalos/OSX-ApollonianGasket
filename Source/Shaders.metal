// https://github.com/portsmouth/snelly (under fractals: apollonian_pt.html)
// also visit: http://paulbourke.net/fractals/apollony/
// lighting effects: https://github.com/shockham/mandelbulb
// apollonian: https://www.shadertoy.com/view/4ds3zn
// apollonian2: https://www.shadertoy.com/view/llKXzh

#include <metal_stdlib>
#import "Shader.h"

using namespace metal;

constant int MAX_MARCHING_STEPS = 255;
constant float MIN_DIST = 0.0;
constant float MAX_DIST = 20; //100.0;
constant float EPSILON = 0.0001;
constant float NE = 0.001;

float scene(float3 pos,Control control);

float3 toRectangular(float3 sph) {
    float ss = sph.x * sin(sph.z);
    return float3( ss * cos(sph.y), ss * sin(sph.y), sph.x * cos(sph.z));
}

float3 toSpherical(float3 rec) {
    return float3(length(rec),
                  atan2(rec.y,rec.x),
                  atan2(sqrt(rec.x*rec.x+rec.y*rec.y), rec.z));
}

float3 getNormal(float3 p, Control control) {
    float x = scene(float3(p.x + NE, p.y     , p.z     ),control) - scene(float3(p.x - NE, p.y     , p.z     ),control);
    float y = scene(float3(p.x     , p.y + NE, p.z     ),control) - scene(float3(p.x     , p.y - NE, p.z     ),control);
    float z = scene(float3(p.x     , p.y     , p.z + NE),control) - scene(float3(p.x     , p.y     , p.z - NE),control);
    return normalize(float3(x * control.color.x, y * control.color.y, z * control.color.z));
}

float3 phong_contrib
(
 float3 diffuse,
 float3 specular,
 float  alpha,
 float3 p,
 float3 eye,
 float3 lightPos,
 float3 lightIntensity,
 Control control
 ) {
    float3 N = getNormal(p,control);
    float3 L = normalize(lightPos - p);
    float3 V = normalize(eye - p);
    float3 R = normalize(reflect(-L, N));
    
    float dotLN = dot(L, N);
    float dotRV = dot(R, V);
    
    if (dotLN < 0.0) {
        // Light not visible from this point on the surface
        return float3(0.0, 0.0, 0.0);
    }
    
    if (dotRV < 0.0) {
        // Light reflection in opposite direction as viewer, apply only diffuse
        // component
        return lightIntensity * (diffuse * dotLN);
    }
    return lightIntensity * (diffuse * dotLN + specular * pow(dotRV, alpha));
}

float calc_AO(float3 pos, float3 nor, Control control) {
    float occ = 0.0;
    float sca = 1.0;
    for(int i=0; i<5; i++) {
        float hr = 0.01 + 0.12*float(i)/4.0;
        float3 aopos =  nor * hr + pos;
        float dd = scene(aopos,control);
        occ += -(dd-hr)*sca;
        sca *= 0.95;
    }
    return clamp( 1.0 - 3.0*occ, 0.0, 1.0 );
}

float soft_shadow(float3 camera, float3 light, float mint, float maxt, float k, Control control) {
    float res = 1.0;
    for(float t = mint; t < maxt;) {
        float h = scene(camera + light * t,control);
        if( h < 0.001) return 0.0;
        
        res = min(res, k * h / t);
        t += h;
    }
    return res;
}

typedef float3 vec3;
typedef float2 vec2;

vec3 zcalcNormal( vec3 pos, Control control)
{
    pos = fract(pos);
    
    vec2 e = vec2(1.0,-1.0) * 0.0057;
    
    return normalize(e.xyy * scene( pos + e.xyy,control ) +
                     e.yyx * scene( pos + e.yyx,control ) +
                     e.yxy * scene( pos + e.yxy,control ) +
                     e.xxx * scene( pos + e.xxx,control ) );
}

float3 lighting(float ambient, float diffuse, float specular, float harshness, float3 p, float3 eye, Control control) {
    float3 color = float3(ambient);
    float3 normal = getNormal(p,control);
    
    color = mix(color, normal, control.lighting.saturation);
    color = mix(color, float3(1.0 - smoothstep(0.0, 0.6, distance(float2(0.0), p.xy))), control.lighting.gamma);
    
    float occ = calc_AO(p, normal,control);
    
    color += phong_contrib(diffuse, specular, harshness, p, eye, control.light, 1, control);
    color = mix(color, color * occ * soft_shadow(p, control.light, control.lighting.shadowMin, control.lighting.shadowMax * 10, control.lighting.shadowMult * 30,control), control.lighting.shadowAmt);
    
    return color;
}

float scene(float3 pos,Control control) {
    const float PI = 3.1415926;
    float scale = 0.001 + control.dali * 5;
    float aa = control.multiplier * 100;
    float k,t = control.foam2 + 0.25 * cos(control.bend * PI * aa * (pos.z - pos.x) / scale);

    // style 1 --------------------------------------
    if(control.style == 1) {
        for( int i=0; i<6; ++i) {
            pos = -1.0 + 2.0 * fract(0.5 * pos + 0.5);
            pos -= sign(pos) * control.foam / 20;
            
            float r2 = dot(pos,pos);
            float k = t / r2; ///control.foam2 / r2;
            pos *= k;
            scale *= k;
        }
        
        float d1 = sqrt( min( min( dot(pos.xy,pos.xy), dot(pos.yz,pos.yz) ), dot(pos.zx,pos.zx) ) ) - 0.02;
        float dmi = min(d1,abs(pos.y));
        return 0.5 * dmi / scale;
    }
    
    // style 0 --------------------------------------
    scale = 0.001 + control.dali;

    for (int i=0; i<10; ++i) {
        pos = -1.0 + 2.0 * fract(0.5 * pos + 0.5);
        k = t / dot(pos,pos);
        pos *= k * control.foam;
        scale *= k * control.foam;
    }

    return 1.5 * (0.25 * abs(pos.y) / scale);
}

float shortest_dist(float3 eye, float3 marchingDirection, Control control) {
    float start = MIN_DIST;
    float end = MAX_DIST;
    float depth = start;
    
    for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
        float dist = scene(eye + depth * marchingDirection,control);
        if (dist < control.minDist) {
            return depth;
        }
        
        depth += dist;
        
        if (depth >= end) {
            return end;
        }
    }
    return end;
}

kernel void rayMarchShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 texture2d<float, access::read> coloringTexture [[texture(1)]],
 constant Control &control [[buffer(0)]],
 uint2 p [[thread_position_in_grid]])
{
    float den = float(control.xSize);
    float dx =  control.zoom * (float(p.x)/den - 0.5);
    float dy = -control.zoom * (float(p.y)/den - 0.5);
    float3 color = float3();
    
    float3 direction = normalize((control.sideVector * dx) + (control.topVector * dy) + control.viewVector);    
    float dist = shortest_dist(control.camera,direction,control);
    
    if (dist <= MAX_DIST - EPSILON) {
        float3 position = control.camera + dist * direction;
        float3 normal = getNormal(position,control);

        // use texture
        if(control.txtOnOff > 0) {
            float scale = control.txtCenter.z * 20;
            float len = length(position) / 4; //distance;
            float x = normal.x * len;
            float y = normal.z * len;
            float w = control.txtSize.x;
            float h = control.txtSize.y;
            float xx = w + (control.txtCenter.x * 10 + x * scale) * (w + len);
            float yy = h + (control.txtCenter.y * 10 + y * scale) * (h + len);
            
            uint2 pt;
            pt.x = uint(fmod(xx,w));
            pt.y = uint(control.txtSize.y - fmod(yy,h)); // flip Y coord
            color = coloringTexture.read(pt).xyz;
        }

        color += lighting(control.lighting.ambient,
                         control.lighting.diffuse,
                         control.lighting.specular,
                         (1 - control.lighting.harshness) * 10,
                         position,
                         control.camera,control);

        color *= (1 - dist/control.fog);        
    }
    
    outTexture.write(float4(color,1),p);
}

