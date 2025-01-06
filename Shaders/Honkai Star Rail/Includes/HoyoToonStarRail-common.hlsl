// from: https://github.com/cnlohr/shadertrixx/blob/main/README.md#best-practice-for-getting-depth-of-a-given-pixel-from-the-depth-texture
float GetLinearZFromZDepth_WorksWithMirrors(float zDepthFromMap, float2 screenUV)
{
	#if defined(UNITY_REVERSED_Z)
	zDepthFromMap = 1 - zDepthFromMap;
			
	// When using a mirror, the far plane is whack.  This just checks for it and aborts.
	if( zDepthFromMap >= 1.0 ) return _ProjectionParams.z;
	#endif

	float4 clipPos = float4(screenUV.xy, zDepthFromMap, 1.0);
	clipPos.xyz = 2.0f * clipPos.xyz - 1.0f;
	float4 camPos = mul(unity_CameraInvProjection, clipPos);
	return -camPos.z / camPos.w;
}

float packed_channel_picker(SamplerState texture_sampler, Texture2D texture_2D, float2 uv, float channel)
{
    float4 packed = texture_2D.Sample(texture_sampler, uv);

    float choice;
    if(channel == 0) {choice = packed.x;}
    else if(channel == 1) {choice = packed.y;}
    else if(channel == 2) {choice = packed.z;}
    else if(channel == 3) {choice = packed.w;}

    return choice;
}

float3 hue_shift(float3 in_color, float material_id, float shift1, float shift2, float shift3, float shift4, float shift5, float shift6, float shift7, float shift8,float shiftglobal, float autobool, float autospeed, float mask)
{  
    #if defined(can_shift) 
        float auto_shift = (_Time.y * autospeed) * autobool; 
        
        float shift[8] = 
        {
            shift1,
            shift2,
            shift3,
            shift4,
            shift5,
            shift6,
            shift7,
            shift8
        };
        
        float shift_all = 0.0f;
        if(shift[material_id] > 0)
        {
            shift_all = shift[material_id] + auto_shift;
        }
        
        auto_shift = (_Time.y * autospeed) * autobool; 
        if(shiftglobal > 0)
        {
            shiftglobal = shiftglobal + auto_shift;
        }
        
        float hue = shift_all + shiftglobal;
        hue = lerp(0.0f, 6.27f, hue);

        float3 k = (float3)0.57735f;
        float cosAngle = cos(hue);

        float3 adjusted_color = in_color * cosAngle + cross(k, in_color) * sin(hue) + k * dot(k, in_color) * (1.0f - cosAngle);

        return lerp(in_color, adjusted_color, mask);
    #else
        return in_color;
    #endif
}


int material_region(float lightmap_alpha)
{
    int material = 0;
    if(lightmap_alpha > 0.5 && lightmap_alpha < 1.5 )
    {
        material = 1;
    } 
    else if(lightmap_alpha > 1.5f && lightmap_alpha < 2.5f)
    {
        material = 2;
    } 
    else if(lightmap_alpha > 2.5f && lightmap_alpha < 3.5f)
    {
        material = 3;
    } 
    else
    {
        material = (lightmap_alpha > 6.5f && lightmap_alpha < 7.5f) ? 7 : 0;
        material = (lightmap_alpha > 5.5f && lightmap_alpha < 6.5f) ? 6 : material;
        material = (lightmap_alpha > 4.5f && lightmap_alpha < 5.5f) ? 5 : material;
        material = (lightmap_alpha > 3.5f && lightmap_alpha < 4.5f) ? 4 : material;
    }

    if(_HairMaterial) material = 0;

    return material;
}

// float shadow_rate(float ndotl, float lightmap_ao, float vertex_ao, float shadow_ramp, float shadow_map)
float shadow_rate(float ndotl, float lightmap_ao, float vertex_ao, float shadow_ramp)
{
    float shadow_ndotl  = ndotl * 0.5f + 0.5f;
    float shadow_thresh = (lightmap_ao + lightmap_ao) * vertex_ao;
    float shadow_area   = min(1.0f, dot(shadow_ndotl.xx, shadow_thresh.xx));
    #ifndef _IS_PASS_LIGHT
        shadow_area = max(0.001f, shadow_area) * 0.85f + 0.15f;
        shadow_area = (shadow_area > shadow_ramp) ? 0.99f : shadow_area;
    #else
        shadow_area = smoothstep(0.5f, 1.0f, shadow_area);
    #endif
    return shadow_area;
}

float shadow_rate_face(float2 uv, float3 light)
{
    #if defined(faceishadow)
        float3 head_forward = normalize(UnityObjectToWorldDir(_headForwardVector.xyz));
        float3 head_right   = normalize(UnityObjectToWorldDir(_headRightVector.xyz));
        float rdotl = dot((head_right.xz),  (light.xz));
        float fdotl = dot((head_forward.xz), (light.xz));

        float2 faceuv = uv;
        if(rdotl > 0.0f )
        {
            faceuv = uv;
        }  
        else
        {
            faceuv = uv * float2(-1.0f, 1.0f) + float2(1.0f, 0.0f);
        }

        float shadow_step = 1.0f - (fdotl * 0.5f + 0.5f);

        // apply rotation offset
        
        // use only the alpha channel of the texture 
        float facemap = _FaceMap.Sample(sampler_linear_repeat, faceuv).w;
        // interpolate between sharp and smooth face shading
        shadow_step = smoothstep(shadow_step - (_FaceSoftness), shadow_step + (_FaceSoftness), facemap);

    #else
        float shadow_step = 1.00f;
    #endif

    return shadow_step;
}

float3 specular_base(float shadow_area, float ndoth, float lightmap_spec, float3 specular_color, float3 specular_values, float3 specular_color_global, float specular_intensity_global)
{
    #if defined(use_specular)
        float3 specular = ndoth;
        specular = pow(max(specular, 0.01f), specular_values.x);
        specular_values.y = max(specular_values.y, 0.001f);

        float specular_thresh = 1.0f - lightmap_spec;
        float rough_thresh = specular_thresh - specular_values.y;
        specular_thresh = (specular_values.y + specular_thresh) - rough_thresh;
        specular = shadow_area * specular - rough_thresh; 
        specular_thresh = saturate((1.0f / specular_thresh) * specular);
        specular = (specular_thresh * - 2.0f + 3.0f) * pow(specular_thresh, 2.0f);
        specular = (specular_color * specular_color_global) * specular * ((specular_values.z * specular_intensity_global) * 0.35f);
        return specular;
    #else
        return (float3)0.00f;
    #endif
}

float extract_fov()
{
    return 2.0f * atan((1.0f / unity_CameraProjection[1][1]))* (180.0f / 3.14159265f);
}

float fov_range(float old_min, float old_max, float value)
{
    float new_value = (value - old_min) / (old_max - old_min);
    return new_value; 
}

// https://github.com/cnlohr/shadertrixx/blob/main/README.md#detecting-if-you-are-on-desktop-vr-camera-etc
bool isVR(){
    // USING_STEREO_MATRICES
    #if UNITY_SINGLE_PASS_STEREO
        return true;
    #else
        return false;
    #endif
}

float remap(float value, float old_min, float old_max, float new_min, float new_max)
{
    return new_min + (value - old_min) * (new_max - new_min) / (old_max - old_min);
}

void dissolve_vertex(vs_in i, out float4 dis_pos, out float4 dis_uv)
{
    #if defined(can_dissolve)
        float2 dissolveUV = lerp(i.uv_0, i.uv_1, _DissolveUV);

        dis_uv = float4(dissolveUV.xy * _DissolveST.xy + _DissolveST.zw, dissolveUV.xy * _DistortionST.xy + _DistortionST.zw);

        dis_pos.x = dissolveUV.x;

        float4 ws_pos = mul(unity_ObjectToWorld, i.vertex);

        float4 dissolvePos = lerp(i.vertex, ws_pos, _DissolvePosMaskWorldON);

        float3 u_xlat1;
        float4 u_xlat2;
        float4 u_xlat3;
        float3 u_xlat16_4;
        float3 u_xlat6;
        float u_xlat16_9;
        float u_xlat16;
        bool u_xlatb16;

        u_xlat1.xyz = dissolvePos;

        u_xlat2.xyz = (-u_xlat1.xyz) + _ES_EffCustomLightPosition.xyz;
        u_xlat1.xyz = (float3)(_DissolvePosMaskGlobalOn) * u_xlat2.xyz + u_xlat1.xyz;
        u_xlat1.xyz = u_xlat1.xyz + (-_DissolvePosMaskRootOffset.xyz);
        u_xlat2.xyz = _ES_EffCustomLightPosition.xyz + (-unity_ObjectToWorld[3].xyz);
        u_xlat3.xyz = (float3)(_DissolvePosMaskWorldON) * (-unity_ObjectToWorld[3].xyz) + _DissolvePosMaskPos.xyz;
        u_xlat2.xyz = u_xlat2.xyz + (-u_xlat3.xyz);
        u_xlat2.xyz = (float3)(_DissolvePosMaskGlobalOn) * u_xlat2.xyz + u_xlat3.xyz;
        u_xlat16_4.x = dot(u_xlat2.xyz, u_xlat2.xyz);
        u_xlat16_4.x = rsqrt(u_xlat16_4.x);
        u_xlat16_4.xyz = u_xlat2.xyz * u_xlat16_4.xxx;
        u_xlat16 = dot(abs(u_xlat2.xyz), float3(1.0, 1.0, 1.0));
        u_xlatb16 = u_xlat16>=0.00100000005;
        u_xlat1.x = dot(u_xlat16_4.xyz, u_xlat1.xyz);
        u_xlat16_4.x = max(_DissolvePosMaskPos.w, 0.00999999978);
        u_xlat16_9 = abs(u_xlat1.x) + u_xlat16_4.x;
        u_xlat16_4.x = u_xlat16_4.x + u_xlat16_4.x;
        u_xlat16_4.x = u_xlat16_9 / u_xlat16_4.x;
        u_xlat16_9 = u_xlat16_4.x * -2.0 + 1.0;
        u_xlat16_4.x = _DissolvePosMaskFilpOn * u_xlat16_9 + u_xlat16_4.x;
        u_xlat16_4.x = u_xlat16_4.x + (-_DissolvePosMaskOn);
        u_xlat16_4.x = u_xlat16_4.x + 1.0;
        u_xlat16_4.x = clamp(u_xlat16_4.x, 0.0, 1.0);
        dis_pos.y = (u_xlatb16) ? u_xlat16_4.x : 1.0;
        dis_pos.zw = float2(0.0, 0.0);
    #endif
}

void dissolve_clip(in float4 ws_pos, in float4 dis_pos, in float4 dis_uv, in float2 uv)
{
    #if defined(can_dissolve)
        float rate = _DissolveRate;
        if(_InvertRate) rate = 1.0 - rate;
        if(_DissolveUseDirection)
        {
            float3 dissolvePos = ws_pos.xyz + (float3)1.99999999e-06;
            dissolvePos.xyz = dissolvePos.xyz + (-_DissolveCenter.xyz);
            dissolvePos = dot(dissolvePos.xyz, _DissolveDiretcionXYZ.xyz);

            float test = 0.0f < dissolvePos ? 2 : int(0);
            if(test == 0) discard;
            // clip(dissolvePos);
        }
        else
        {
            float2 dissolveUV = dis_uv.zw + (float2)3.00000011e-06;
            dissolveUV = _DissolveUVSpeed.zw * _Time.yy + dissolveUV.xy;

            float2 dissolveMap = _DissolveMap.Sample(sampler_linear_repeat, dissolveUV);
            dissolveMap.xy = -(dissolveMap + - 0.5f) * (float2)(_DissolveDistortionIntensity) + dis_uv.xy;

            dissolveUV = _DissolveUVSpeed.xy * _Time.yy + dissolveMap.xy;
            dissolveMap = _DissolveMap.Sample(sampler_linear_repeat, dissolveUV).zz + _DissolveMapAdd;

            float4 dissolveMask = _DissolveMask.Sample(sampler_linear_repeat, uv);

            dissolveMask.x = dot(dissolveMask, _DissolveComponent);

            float dissolve = (-dis_pos.x) + _DissoveDirecMask;
            dissolve.x = min(abs(dissolve.x), 1.0);

            dissolve.x = dissolve.x * dissolveMap;
            dissolve.x = dissolveMask.x * dissolve.x;
            dissolve.x = dissolve.x * dis_pos.y;
            dissolve.x = dissolve.x * 1.00999999 + -0.00999999978;
            dissolve.x = dissolve.x + (-rate);
            dissolve.x = dissolve.x + 1.0;
            dissolve.x = floor(dissolve.x);
            dissolve.x = max(dissolve.x, 0.0);

            if((int)dissolve.x == 0) discard;
        }
    #endif
}

void dissolve_color(float4 ws_pos, float4 dis_pos, float4 dis_uv, float2 uv,in float4 diffuse, inout float4 color)
{
    #if defined(can_dissolve)
        float rate = _DissolveRate;
        if(_InvertRate) rate = 1.0 - rate;
        if(_DissolveUseDirection)
        {
            float3 u_xlat2  = ws_pos.xyz + (-_DissolveCenter.xyz);
            float u_xlat0 = dot(u_xlat2.xyz, _DissolveDiretcionXYZ.xyz);
            int test = 0.0<u_xlat0 ? (int)2 : (int)0;
            if((test)==0){discard;}
        }
        else
        {
            float dissolveDirMask =  (-dis_pos.x) + _DissoveDirecMask;
            dissolveDirMask = min(abs(dissolveDirMask), 1.0);

            float2 dissolveUV = _DissolveUVSpeed.zw * _Time.yy + dis_uv.zw;
            float2 dissolveMap = _DissolveMap.Sample(sampler_linear_repeat, dissolveUV).xy;
            dissolveMap = -(dissolveMap + -0.5f) * _DissolveDistortionIntensity.xx + dis_uv.xy;
            dissolveMap = _DissolveUVSpeed.xy * _Time.yy + dissolveMap;

            dissolveMap.x = _DissolveMap.Sample(sampler_linear_repeat, dissolveMap).z + _DissolveMapAdd;
            float4 dissolveMask = _DissolveMask.Sample(sampler_linear_repeat, uv);
            dissolveMask.x = dot(dissolveMask, _DissolveComponent);
            dissolveDirMask = dissolveDirMask * dissolveMap;
            dissolveDirMask = dissolveMask.x * dissolveDirMask;
            dissolveDirMask = dissolveDirMask * dis_pos.y;
            dissolveDirMask = dissolveDirMask * 1.00999999 + -0.00999999978;
            // float dissolveRate = dissolveDirMask + (-_DissolveRate);
            // dissolveRate = dissolveRate + 1.0;
            // dissolveRate = floor(dissolveDirMask);
            // dissolveRate = max(dissolveRate, 0.0);
            // if((int)dissolveRate == 0) discard;
            // the above is redundent code since its essentially handled in the dissolve_vertex function above.
            
            float4 u_xlat16_8;
            float4 u_xlat16_11;
            float4 u_xlat16_12;
            float4 u_xlat16_18;
            float4 u_xlat2;
            float4 u_xlat4;
            float4 u_xlat7;
            float4 u_xlat16_3;
            float4 u_xlat16_5;
            float4 u_xlat16_23;
            float4 u_xlat16_38;
            float4 u_xlat16_0;
            float4 u_xlat16_1;
            float4 u_xlat16_2;
            float4 u_xlat16_4;
            float4 u_xlat16_6;


            u_xlat16_8.x = rate + _DissolveOutlineSize1;
            u_xlat16_8.y = u_xlat16_8.x + (-_DissolveOutlineSize2);
            u_xlat16_8.xy = dissolveDirMask.xx + (-u_xlat16_8.xy);
            u_xlat16_38.xy = _DissolveOutlineSmoothStep.xy + 0.00100000005f;
            u_xlat16_38.xy = float2(1.0, 1.0) / u_xlat16_38.xy;
            u_xlat16_8.xy = u_xlat16_38.xy * u_xlat16_8.xy;
            u_xlat16_8.xy = clamp(u_xlat16_8.xy, 0.0, 1.0);
            u_xlat16_11.xyz = diffuse.xyz * dissolveMap.x + _DissolveOutlineOffset;
            u_xlat16_12.xyz = u_xlat16_11.xyz * _DissolveOutlineColor1.xyz;
            u_xlat16_11.xyz = u_xlat16_11.xyz * _DissolveOutlineColor2.xyz + (-u_xlat16_12.xyz);
            u_xlat16_23.xyz = u_xlat16_8.yyy * u_xlat16_11.xyz + u_xlat16_12.xyz;
            u_xlat16_3.x = u_xlat16_8.x + 1.0;
            u_xlat16_3.x = u_xlat16_3.x + (-_DissolveOutlineColor1.w);
            u_xlat16_3.x = clamp(u_xlat16_3.x, 0.0, 1.0);
            u_xlat16_18.xyz = color.xyz * 1.0f + (-u_xlat16_23.xyz);
            u_xlat16_18.xyz = u_xlat16_3.xxx * u_xlat16_18.xyz + u_xlat16_23.xyz;
            u_xlat2.xyz = u_xlat16_18.xyz * 278.508514f + 10.7771997f;
            u_xlat2.xyz = u_xlat2.xyz * u_xlat16_18.xyz;
            u_xlat4.xyz = u_xlat16_18.xyz * 298.604492f + 88.7121964f;
            u_xlat4.xyz = u_xlat16_18.xyz * u_xlat4.xyz + 80.6889038f;
            u_xlat2.xyz = u_xlat2.xyz / u_xlat4.xyz;
            u_xlat4.xyz = (-u_xlat2.xyz) + u_xlat16_18.xyz;
            u_xlat7.xyz = u_xlat16_3.xxx * u_xlat4.xyz + u_xlat2.xyz;
            color.xyz = u_xlat7.xyz;

        }
    #endif
}

void heightlightlerp(float4 pos, inout float4 color)
{
    // (u_xlat75 = (vs_TEXCOORD2.y + (-_CharaWorldSpaceOffset.y)));
    // (u_xlat16_30.x = max(_ES_HeightLerpBottom, 0.001));
    // (u_xlat76 = (1.0 / u_xlat16_30.x));
    // (u_xlat76 = (u_xlat75 * u_xlat76));
    // (u_xlat76 = clamp(u_xlat76, 0.0, 1.0));
    // (u_xlat2.x = ((u_xlat76 * -2.0) + 3.0));
    // (u_xlat76 = (u_xlat76 * u_xlat76));
    // (u_xlat76 = (((-u_xlat2.x) * u_xlat76) + 1.0));
    // (u_xlat75 = (u_xlat75 + (-_ES_HeightLerpTop)));
    // (u_xlat75 = (u_xlat75 + u_xlat75));
    // (u_xlat75 = clamp(u_xlat75, 0.0, 1.0));
    // (u_xlat2.x = ((u_xlat75 * -2.0) + 3.0));
    // (u_xlat75 = (u_xlat75 * u_xlat75));
    // (u_xlat27 = (u_xlat75 * u_xlat2.x));
    // (u_xlat16_30.x = ((-u_xlat76) + 1.0));
    // (u_xlat16_30.x = (((-u_xlat2.x) * u_xlat75) + u_xlat16_30.x));
    // (u_xlat16_30.x = clamp(u_xlat16_30.x, 0.0, 1.0));
    // (u_xlat16_7.xyz = (vec3(u_xlat76) * _ES_HeightLerpBottomColor.xyz));
    // (u_xlat16_30.xyz = (u_xlat16_30.xxx * _ES_HeightLerpMiddleColor.xyz));
    // (u_xlat16_30.xyz = (u_xlat16_30.xyz * _ES_HeightLerpMiddleColor.www));
    // (u_xlat16_30.xyz = ((u_xlat16_7.xyz * _ES_HeightLerpBottomColor.www) + u_xlat16_30.xyz));
    // (u_xlat16_7.xyz = (vec3(u_xlat27) * _ES_HeightLerpTopColor.xyz));
    // (u_xlat16_30.xyz = ((u_xlat16_7.xyz * _ES_HeightLerpTopColor.www) + u_xlat16_30.xyz));
    // (u_xlat16_30.xyz = clamp(u_xlat16_30.xyz, 0.0, 1.0));
    // (u_xlat16_30.xyz = (u_xlat16_30.xyz * u_xlat16_8.xyz));
    // (u_xlat16_30.xyz = (u_xlat16_30.xyz + u_xlat16_30.xyz));

    float height = pos.y + (-_CharaWorldSpaceOffset);

    float4 u_xlat16_30;
    float u_xlat75;
    float u_xlat76;
    float4 u_xlat2;
    float u_xlat27;
    float4 u_xlat16_7;

    u_xlat75 = height;

    (u_xlat16_30.x = max(_ES_HeightLerpBottom, 0.001));
    (u_xlat76 = (1.0 / u_xlat16_30.x));
    (u_xlat76 = (u_xlat75 * u_xlat76));
    (u_xlat76 = clamp(u_xlat76, 0.0, 1.0));
    (u_xlat2.x = ((u_xlat76 * -2.0) + 3.0));
    (u_xlat76 = (u_xlat76 * u_xlat76));
    (u_xlat76 = (((-u_xlat2.x) * u_xlat76) + 1.0));
    (u_xlat75 = (u_xlat75 + (-_ES_HeightLerpTop)));
    (u_xlat75 = (u_xlat75 + u_xlat75));
    (u_xlat75 = clamp(u_xlat75, 0.0, 1.0));
    (u_xlat2.x = ((u_xlat75 * -2.0) + 3.0));
    (u_xlat75 = (u_xlat75 * u_xlat75));
    (u_xlat27 = (u_xlat75 * u_xlat2.x));
    (u_xlat16_30.x = ((-u_xlat76) + 1.0));
    (u_xlat16_30.x = (((-u_xlat2.x) * u_xlat75) + u_xlat16_30.x));
    (u_xlat16_30.x = clamp(u_xlat16_30.x, 0.0, 1.0));
    (u_xlat16_7.xyz = ((float3)(u_xlat76) * _ES_HeightLerpBottomColor.xyz));
    (u_xlat16_30.xyz = (u_xlat16_30.xxx * _ES_HeightLerpMiddleColor.xyz));
    (u_xlat16_30.xyz = (u_xlat16_30.xyz * _ES_HeightLerpMiddleColor.www));
    (u_xlat16_30.xyz = ((u_xlat16_7.xyz * _ES_HeightLerpBottomColor.www) + u_xlat16_30.xyz));
    (u_xlat16_7.xyz = ((float3)(u_xlat27) * _ES_HeightLerpTopColor.xyz));
    (u_xlat16_30.xyz = ((u_xlat16_7.xyz * _ES_HeightLerpTopColor.www) + u_xlat16_30.xyz));
    (u_xlat16_30.xyz = clamp(u_xlat16_30.xyz, 0.0, 1.0));
    (u_xlat16_30.xyz = (u_xlat16_30.xyz * color.xyz));
    // (u_xlat16_30.xyz = (u_xlat16_30.xyz + u_xlat16_30.xyz));
    color.xyz = u_xlat16_30;

}

void swirl_dissolve(vs_out i, inout float4 output)
{
    float4 dis_color = i.v_col;
    float disappear_range = dis_color.w * _DisStep.x;
    dis_color.w = lerp(1.0f, _Disappear, disappear_range);
    dis_color.xyz = dis_color.xyz * _InsideColor;

    float2 _MaskCheck = (-i.uv.xy) + _MaskTex_ST.zw;
    _MaskCheck = min(abs(_MaskCheck.xy), float2(1.0, 1.0));
    float2 mask_uv = _MaskON ? i.uv.xy * _MaskTex_ST.xy + _MaskTex_ST.zw : _MaskCheck; 
    // vs_TEXCOORD0.zw

    
    float2 main_uv = i.uv.xy * _MainTex_ST.xy + _MainTex_ST.zw; // vs_TEXCOORD0.xy
    float2 dissolve_uv = i.uv.xy * _DisTex_ST.xy + _DisTex_ST.zw; // vs_TEXCOORD1.xy
    main_uv = _Time.yy * _MainSpeed.xy + main_uv;
    dissolve_uv = _Time.yy * _DisRSpeed.xy + dissolve_uv;

    float4 u_xlat16_0;
    float4 u_xlat1;
    float4 u_xlat16_1;
    bool u_xlatb1;
    float3 u_xlat16_2;
    float4 u_xlat16_3;
    float4 u_xlat4;
    float4 u_xlat16_5;
    float u_xlat16_6;
    float u_xlat7;
    float u_xlat16_8;
    float u_xlat10;
    float u_xlat16_12;
    float u_xlat16_14;
    float u_xlat16;
    bool u_xlatb16;
    float u_xlat16_18;


    u_xlat16_0.xyz = _MaskChannel.xyz;
    u_xlat16_0.w = _MaskChannelA;
    u_xlat16_1 = _MaskTex.Sample(sampler_linear_repeat, mask_uv);
    u_xlat16_0.x = dot(u_xlat16_1, u_xlat16_0);
    u_xlat16_6 = dot(u_xlat16_1, _MaskTransparencyChannel);

    u_xlat7 = mask_uv.y * mask_uv.x;
    u_xlat1.x = (_MaskON) ? u_xlat16_0.x : u_xlat7;
    u_xlat16_2.x = dis_color.w;
    u_xlat7 = _DisTex.Sample(sampler_linear_repeat, dissolve_uv).x;
    dissolve_uv.y = dissolve_uv.y + 0.5f;
    u_xlat16_0.x = u_xlat7 + _DisRSpeed.z;
    u_xlat16_12 = (_Mid != 0) ? u_xlat7 : 1.0;
    u_xlat16_2.y = dis_color.w + _DisStep.y;
    u_xlat16_2.z = u_xlat16_2.y + _SmoothStep.w;
    u_xlat16_2.xyz = u_xlat1.xxx * u_xlat16_0.xxx + (-u_xlat16_2.xyz);
    u_xlat16_3.xyz = 1.0 / _SmoothStep.xyz;
    u_xlat16_2.xyz = u_xlat16_2.xyz * u_xlat16_3.xyz;

    u_xlat16_2.xyz = clamp(u_xlat16_2.xyz, 0.0, 1.0);

    u_xlat16_0.x = (_Mid != 0) ? u_xlat16_2.z : 0.0;
    u_xlat1 = _MainTex.Sample(sampler_linear_repeat, main_uv);
    u_xlat16_18 = dot(_MainChannel, u_xlat1);
    u_xlat16_3.y = u_xlat16_18 * u_xlat1.w;
    u_xlat16_3.x = dot(_MainChannelRGB, u_xlat1);
    u_xlat16_3 = u_xlat16_3.xxxy;

    u_xlat16_3 = clamp(u_xlat16_3, 0.0, 1.0);

    u_xlat16_3 = (_CL == 2) ? u_xlat16_3 : u_xlat1;
    u_xlat16_18 = dot(u_xlat1.xyz, _MainChannel.xyz);
    u_xlat16_5.w = u_xlat16_18 * u_xlat1.w;

    u_xlat16_5.w = clamp(u_xlat16_5.w, 0.0, 1.0);

    u_xlat16_5.xyz = u_xlat1.xyz + _MainChannel.www;

    u_xlat16_5.xyz = clamp(u_xlat16_5.xyz, 0.0, 1.0);

    u_xlat16_1 = (_CL == 1) ? u_xlat16_5 : u_xlat16_3;
    u_xlat16_3.xyz = u_xlat16_1.xyz * u_xlat16_12 + _MainSpeed.www;
    u_xlat16_5.xyz = u_xlat16_3.xyz * _OutSideColor.xyz;
    u_xlat16_3.xyz = _MidColor.xyz * u_xlat16_3.xyz + (-u_xlat16_5.xyz);
    u_xlat16_0.xzw = u_xlat16_0.xxx * u_xlat16_3.xyz + u_xlat16_5.xyz;
    u_xlat16_3.xyz = dis_color.xyz * u_xlat16_1.xyz + (-u_xlat16_0.xzw);
    u_xlat16_0.xzw = u_xlat16_2.yyy * u_xlat16_3.xyz + u_xlat16_0.xzw;
    u_xlat16_2.x = u_xlat16_1.w * u_xlat16_2.x;
    u_xlat16_2.x = u_xlat16_2.x * _MidColor.w;
    u_xlat16_0.xzw = u_xlat16_0.xzw * _MainSpeed.zzz;
    u_xlat16_8 = 1;
    u_xlat16_0.xzw = u_xlat16_0.xzw * u_xlat16_8;
    u_xlat16_8 = 1;
    u_xlat16_0.xzw = u_xlat16_0.xzw * u_xlat16_8;
    u_xlat16_0.xzw = u_xlat16_0.xzw * 1;
    u_xlat16_8 = max(u_xlat16_0.z, u_xlat16_0.x);
    u_xlat16_8 = max(u_xlat16_0.w, u_xlat16_8);
    u_xlat16_14 = _MaskTransparency * _MaskON;

    u_xlat16_6 = (u_xlat16_14 == 0) ? u_xlat16_6 : 1.0;
    u_xlat16_6 = u_xlat16_6 * u_xlat16_2.x;
    u_xlat16_6 = u_xlat16_6 * 10.0;

    u_xlat16_6 = clamp(u_xlat16_6, 0.0, 1.0);

    u_xlat16_2.x = u_xlat16_6 * u_xlat16_8;
    output.w = u_xlat16_6;
    u_xlat4.x = max(u_xlat16_2.x, 0.00999999978);
    u_xlat10 = u_xlat4.x + (-_ES_EP_EffectParticleBottom);
    u_xlat16 = (-_ES_EP_EffectParticleBottom) + _ES_EP_EffectParticleTop;
    u_xlat16 = 1.0 / u_xlat16;
    u_xlat10 = u_xlat16 * u_xlat10;

    u_xlat10 = clamp(u_xlat10, 0.0, 1.0);

    u_xlat16 = u_xlat10 * -2.0 + 3.0;
    u_xlat10 = u_xlat10 * u_xlat10;
    u_xlat10 = u_xlat10 * u_xlat16;
    u_xlat16_6 = (-_ES_EP_EffectParticleBottom) + _ES_EP_EffectParticleTop;
    u_xlat16_6 = u_xlat10 * u_xlat16_6 + _ES_EP_EffectParticleBottom;
    u_xlat10 = (-u_xlat4.x) + u_xlat16_6;
    u_xlat10 = _ES_EP_EffectParticle * u_xlat10 + u_xlat4.x;

    u_xlatb16 = _ES_EP_EffectParticleBottom<u_xlat4.x;

    u_xlat10 = (u_xlatb16) ? u_xlat10 : u_xlat4.x;
    u_xlat4.xzw = u_xlat16_0.xzw / u_xlat4.xxx;
    u_xlat4.xyz = u_xlat10 * u_xlat4.xzw;
    output.xyz = u_xlat4.xyz;
    return;
}

float4 starry_sky(float4 color, float4 diffuse, float2 uv)
{
    if(_StarrySky)
    {
        float2 sky_uv = uv * _SkyTex_ST.xy + _SkyTex_ST.zw;
        float2 mask_uv = uv * _SkyMask_ST.xy + _SkyMask_ST.zw;
        float3 sky_tex = _SkyTex.Sample(sampler_linear_repeat, sky_uv);
        float sky_mask = _SkyMask.Sample(sampler_linear_repeat, mask_uv).x;

        float3 colored = diffuse * color;
        diffuse.xyz = -diffuse * color + sky_tex;
        diffuse.xyz = (sky_mask + _SkyRange) * diffuse + colored;
        return diffuse;
    }
    else
    {
        return diffuse * color;
    }
}

float4 starry_cloak(float4 sspos, float3 view, float2 uv, float4 position, float3 tangents, float4 out_color)
{
    float4 output;

    float2 star_uv = sspos.xy/sspos.ww;

    star_uv = length(view) * (star_uv + (float2)-0.5f) * _SkyStarDepthScale;
    star_uv = star_uv * _SkyStarTex_ST.xy + _SkyStarTex_ST.zw;
    star_uv = _Time.yy * _SkyStarSpeed.xy + star_uv;
    float3 skystar = (_SkyStarTex.Sample(sampler_linear_repeat, star_uv).xxx * _SkyStarColor) * _SkyStarTexScale.x;
    // output.xyz = output.xyz * ;

    float2 skymask = ((_SkyMask.Sample(sampler_linear_repeat, uv * _SkyMask_ST.xy + _SkyMask_ST.zw).xy + _SkyRange));

    float2 mask_uv = uv.xy * _SkyStarMaskTex_ST.xy + _SkyStarMaskTex_ST.zw;
    mask_uv = _Time.yy * _SkyStarMaskTexSpeed.xx + mask_uv;
    float mask = _SkyStarMaskTex.Sample(sampler_linear_repeat, mask_uv).x * _SkyStarMaskTexScale;
    // output.xyz = output.xyz * mask;

    float4 pos = mul(UNITY_MATRIX_V, position);
    pos.xyz = pos / float3(_OSScale, _OSScale.xx * 0.5.xx);

    float3 spos = smoothstep(1.0f, -1.0f, position.yzx / (_OSScale * float3(0.5f, 0.5f, 1.0f)));

    float2 pos_star_uv = spos.yz * 20.0f;

    float star_tex_w = _SkyStarTex.Sample(sampler_linear_repeat, pos_star_uv).w;
    float2 star_tex_yz = _SkyStarTex.Sample(sampler_linear_repeat, uv).yz;

    float star_density = -star_tex_yz.x * _StarDensity + star_tex_w;
    
    star_density = saturate(star_density / (-_StarDensity  + 1.0f));

    float4 u_xlat6 = spos.xzyz * _SkyStarTex_ST.xyxy + _SkyStarTex_ST.zwzw;
    float u_xlat16_48 = _SkyStarTex.Sample(sampler_linear_repeat, u_xlat6.xy).x;
    float u_xlat16_49 = _SkyStarTex.Sample(sampler_linear_repeat, u_xlat6.zw).x;

    float star_blend = lerp(u_xlat16_49, u_xlat16_48, star_tex_yz.y);

    float3 stars = star_blend * (star_density * _SkyStarColor) * _SkyStarTexScale;

    tangents = normalize(tangents);

    // tangents = normalize(mul((float3x3)unity_MatrixV, tangents));

    float tdotv = dot(tangents, view);

    float test = pow(1.0f - tdotv, 4.0f);

    float u_xlat16_53 = _SkyFresnelSmooth + 0.5;
    float2 u_xlat16_12 = (-float2(_SkyFresnelSmooth, _SkyFresnelBaise)) + float2(0.5, 1.0);
    float u_xlat16_3 = u_xlat16_12.y * test.x + _SkyFresnelBaise;
    u_xlat16_53 = u_xlat16_53 + (-u_xlat16_12.x);
    u_xlat16_3.x = (-u_xlat16_12.x) + u_xlat16_3.x;
    u_xlat16_53 = float(1.0) / u_xlat16_53;
    u_xlat16_3.x = u_xlat16_3.x * u_xlat16_53;
    u_xlat16_3.x = clamp(u_xlat16_3.x, 0.0, 1.0);
    u_xlat16_53 = u_xlat16_3.x * -2.0 + 3.0;
    u_xlat16_3.x = u_xlat16_3.x * u_xlat16_3.x;
    u_xlat16_3.x = u_xlat16_3.x * u_xlat16_53;

    float3 star_fresnel = (u_xlat16_3.xxx * _SkyFresnelScale) * _SkyFresnelColor;
    
    float3 something = skystar.xyz * mask;
    something = something * skymask.x;

    output.xyz = (stars * skymask.x) * mask + -something;
    output.xyz = _StarMode * output.xyz + something;
    output.xyz = star_fresnel * skymask.y + output.xyz;

    // u_xlat16_7.xyz = u_xlat16_8.xyz * u_xlat16_7.xyz + (-u_xlat16_13.xyz);
    // u_xlat16_7.xyz = float3(float3(_StarMode, _StarMode, _StarMode)) * u_xlat16_7.xyz + u_xlat16_13.xyz;
    // u_xlat16_7.xyz = u_xlat16_12.xyz * u_xlat34.yyy + u_xlat16_7.xyz;
    // u_xlat16_3.xyz = u_xlat16_19.xyz * u_xlat16_5.xyz + u_xlat16_7.xyz;
    if(_StarsAreDiffuse) out_color.xyz = lerp(out_color.xyz, 0.0f, skymask.x);
    output.xyz = output.xyz + out_color.xyz;

    // output.xyz = star_fresnel;
    output.w = out_color.w;
    return output;
}

float3 DecodeLightProbe( float3 N )
{
    return ShadeSH9(float4(N,1));
}