uniform sampler2D u_DiffuseMap;

#if defined(USE_LIGHTMAP)
uniform sampler2D u_LightMap;
#endif

#if defined(USE_NORMALMAP)
uniform sampler2D u_NormalMap;
#endif

#if defined(USE_DELUXEMAP)
uniform sampler2D u_DeluxeMap;
#endif

#if defined(USE_SPECULARMAP)
uniform sampler2D u_SpecularMap;
#endif

#if defined(USE_SHADOWMAP)
uniform sampler2D u_ShadowMap;
#endif

#if defined(USE_CUBEMAP)
uniform samplerCube u_CubeMap;
#endif

#if defined(USE_NORMALMAP) || defined(USE_DELUXEMAP) || defined(USE_SPECULARMAP) || defined(USE_CUBEMAP)
// y = deluxe, w = cube
uniform vec4      u_EnableTextures; 
#endif

#if defined(USE_LIGHT_VECTOR) && !defined(USE_FAST_LIGHT)
uniform vec3      u_DirectedLight;
uniform vec3      u_AmbientLight;
#endif

#if defined(USE_PRIMARY_LIGHT) || defined(USE_SHADOWMAP)
uniform vec3  u_PrimaryLightColor;
uniform vec3  u_PrimaryLightAmbient;
#endif

#if defined(USE_LIGHT) && !defined(USE_FAST_LIGHT)
uniform vec4      u_NormalScale;
uniform vec4      u_SpecularScale;
#endif

#if defined(USE_LIGHT) && !defined(USE_FAST_LIGHT)
#if defined(USE_CUBEMAP)
uniform vec4      u_CubeMapInfo;
#endif
#endif

varying vec4      var_TexCoords;

varying vec4      var_Color;

#if (defined(USE_LIGHT) && !defined(USE_FAST_LIGHT))
  #if defined(USE_VERT_TANGENT_SPACE)
varying vec4   var_Normal;
varying vec4   var_Tangent;
varying vec4   var_Bitangent;
  #else
varying vec3   var_Normal;
varying vec3   var_ViewDir;
  #endif
#endif

#if defined(USE_LIGHT) && !defined(USE_FAST_LIGHT)
varying vec4      var_LightDir;
#endif

#if defined(USE_PRIMARY_LIGHT) || defined(USE_SHADOWMAP)
varying vec4      var_PrimaryLightDir;
#endif


#define EPSILON 0.00000001

#if defined(USE_PARALLAXMAP)
float SampleDepth(sampler2D normalMap, vec2 t)
{
  #if defined(SWIZZLE_NORMALMAP)
	return 1.0 - texture2D(normalMap, t).r;
  #else
	return 1.0 - texture2D(normalMap, t).a;
  #endif
}

float RayIntersectDisplaceMap(vec2 dp, vec2 ds, sampler2D normalMap)
{
	const int linearSearchSteps = 16;
	const int binarySearchSteps = 6;

	// current size of search window
	float size = 1.0 / float(linearSearchSteps);

	// current depth position
	float depth = 0.0;

	// best match found (starts with last position 1.0)
	float bestDepth = 1.0;

	// texture depth at best depth
	float texDepth = 0.0;

	float prevT = SampleDepth(normalMap, dp);
	float prevTexDepth = prevT;

	// search front to back for first point inside object
	for(int i = 0; i < linearSearchSteps - 1; ++i)
	{
		depth += size;
		
		float t = SampleDepth(normalMap, dp + ds * depth);
		
		if(bestDepth > 0.996)		// if no depth found yet
			if(depth >= t)
			{
				bestDepth = depth;	// store best depth
				texDepth = t;
				prevTexDepth = prevT;
			}
		prevT = t;
	}

	depth = bestDepth;

#if !defined (USE_RELIEFMAP)
	float div = 1.0 / (1.0 + (prevTexDepth - texDepth) * float(linearSearchSteps));
	bestDepth -= (depth - size - prevTexDepth) * div;
#else
	// recurse around first point (depth) for closest match
	for(int i = 0; i < binarySearchSteps; ++i)
	{
		size *= 0.5;

		float t = SampleDepth(normalMap, dp + ds * depth);
		
		if(depth >= t)
		{
			bestDepth = depth;
			depth -= 2.0 * size;
		}

		depth += size;
	}
#endif

	return bestDepth;
}
#endif

vec3 CalcDiffuse(vec3 diffuseAlbedo, float EH, float NH, float roughness)
{
#if defined(USE_BURLEY)
	// modified from https://disney-animation.s3.amazonaws.com/library/s2012_pbs_disney_brdf_notes_v2.pdf
	float fd90 = -0.5 + EH * EH * roughness;
	float burley = 1.0 + fd90 * 0.04 / NH;
	burley *= burley;
	return diffuseAlbedo * burley;
#else
	return diffuseAlbedo;
#endif
}

vec3 EnvironmentBRDF(float roughness, float NE, vec3 specular)
{
	// from http://community.arm.com/servlet/JiveServlet/download/96891546-19496/siggraph2015-mmg-renaldas-slides.pdf
	float v = 1.0 - max(roughness, NE);
	v *= v * v;
	return vec3(v) + specular;
}

vec3 CalcSpecular(vec3 specular, float NH, float NL, float NE, float EH, float roughness)
{
	// from http://community.arm.com/servlet/JiveServlet/download/96891546-19496/siggraph2015-mmg-renaldas-slides.pdf
	float rr = roughness*roughness;
	float rrrr = rr*rr;
	float d = (NH * NH) * (rrrr - 1.0) + 1.0;
	float v = (EH * EH) * (roughness + 0.5);
	return specular * (rrrr / (4.0 * d * d * v));
}


float CalcLightAttenuation(float point, float normDist)
{
	// zero light at 1.0, approximating q3 style
	// also don't attenuate directional light
	float attenuation = (0.5 * normDist - 1.5) * point + 1.0;

	// clamp attenuation
	#if defined(NO_LIGHT_CLAMP)
	attenuation = max(attenuation, 0.0);
	#else
	attenuation = clamp(attenuation, 0.0, 1.0);
	#endif

	return attenuation;
}

// from http://www.thetenthplanet.de/archives/1180
mat3 cotangent_frame( vec3 N, vec3 p, vec2 uv )
{
	// get edge vectors of the pixel triangle
	vec3 dp1 = dFdx( p );
	vec3 dp2 = dFdy( p );
	vec2 duv1 = dFdx( uv );
	vec2 duv2 = dFdy( uv );

	// solve the linear system
	vec3 dp2perp = cross( dp2, N );
	vec3 dp1perp = cross( N, dp1 );
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame 
	float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
	return mat3( T * invmax, B * invmax, N );
}

void main()
{
	vec3 viewDir, lightColor, ambientColor;
	vec3 L, N, E, H;
	float NL, NH, NE, EH, attenuation;

#if defined(USE_LIGHT) && !defined(USE_FAST_LIGHT)
  #if defined(USE_VERT_TANGENT_SPACE)
	mat3 tangentToWorld = mat3(var_Tangent.xyz, var_Bitangent.xyz, var_Normal.xyz);
	viewDir = vec3(var_Normal.w, var_Tangent.w, var_Bitangent.w);
  #else
	mat3 tangentToWorld = cotangent_frame(var_Normal, -var_ViewDir, var_TexCoords.xy);
	viewDir = var_ViewDir;
  #endif

	E = normalize(viewDir);

	L = var_LightDir.xyz;
  #if defined(USE_DELUXEMAP)
	L += (texture2D(u_DeluxeMap, var_TexCoords.zw).xyz - vec3(0.5)) * u_EnableTextures.y;
  #endif
	float sqrLightDist = dot(L, L);
#endif

#if defined(USE_LIGHTMAP)
	vec4 lightmapColor = texture2D(u_LightMap, var_TexCoords.zw);
  #if defined(RGBM_LIGHTMAP)
	lightmapColor.rgb *= lightmapColor.a;
  #endif
#endif

	vec2 texCoords = var_TexCoords.xy;

#if defined(USE_PARALLAXMAP)
	vec3 offsetDir = viewDir * tangentToWorld;

	offsetDir.xy *= -u_NormalScale.a / offsetDir.z;

	texCoords += offsetDir.xy * RayIntersectDisplaceMap(texCoords, offsetDir.xy, u_NormalMap);
#endif

	vec4 diffuse = texture2D(u_DiffuseMap, texCoords);

#if defined(USE_LIGHT) && !defined(USE_FAST_LIGHT)
  #if defined(USE_LIGHTMAP)
	lightColor   = lightmapColor.rgb * var_Color.rgb;
	ambientColor = vec3(0.0);
	attenuation  = 1.0;
  #elif defined(USE_LIGHT_VECTOR)
	lightColor   = u_DirectedLight * var_Color.rgb;
	ambientColor = u_AmbientLight * var_Color.rgb;
	attenuation  = CalcLightAttenuation(float(var_LightDir.w > 0.0), var_LightDir.w / sqrLightDist);
  #elif defined(USE_LIGHT_VERTEX)
	lightColor   = var_Color.rgb;
	ambientColor = vec3(0.0);
	attenuation  = 1.0;
  #endif

  #if defined(r_lightGamma)
	lightColor   = pow(lightColor,   vec3(r_lightGamma));
	ambientColor = pow(ambientColor, vec3(r_lightGamma));
  #endif

  #if defined(USE_NORMALMAP)
    #if defined(SWIZZLE_NORMALMAP)
	N.xy = texture2D(u_NormalMap, texCoords).ag - vec2(0.5);
    #else
	N.xy = texture2D(u_NormalMap, texCoords).rg - vec2(0.5);
    #endif
	N.xy *= u_NormalScale.xy;
	N.z = sqrt(clamp((0.25 - N.x * N.x) - N.y * N.y, 0.0, 1.0));
	N = tangentToWorld * N;
  #else
	N = var_Normal.xyz;
  #endif

	N = normalize(N);
	L /= sqrt(sqrLightDist);

  #if defined(USE_SHADOWMAP) 
	vec2 shadowTex = gl_FragCoord.xy * r_FBufScale;
	float shadowValue = texture2D(u_ShadowMap, shadowTex).r;

	// surfaces not facing the light are always shadowed
	shadowValue *= float(dot(var_Normal.xyz, var_PrimaryLightDir.xyz) > 0.0);

    #if defined(SHADOWMAP_MODULATE)
	lightColor *= shadowValue * (1.0 - u_PrimaryLightAmbient.r) + u_PrimaryLightAmbient.r;
    #endif
  #endif

  #if defined(USE_LIGHTMAP) || defined(USE_LIGHT_VERTEX)
	ambientColor = lightColor;
	float surfNL = clamp(dot(var_Normal.xyz, L), 0.0, 1.0);

	// Scale the incoming light to compensate for the baked-in light angle
	// attenuation.
	lightColor /= max(surfNL, 0.25);

	// Recover any unused light as ambient, in case attenuation is over 4x or
	// light is below the surface
	ambientColor = clamp(ambientColor - lightColor * surfNL, 0.0, 1.0);
  #endif
  
	vec3 reflectance;

	NL = clamp(dot(N, L), 0.0, 1.0);
	NE = clamp(dot(N, E), 0.0, 1.0);

  #if defined(USE_SPECULARMAP)
	vec4 specular = texture2D(u_SpecularMap, texCoords);
  #else
	vec4 specular = vec4(1.0);
  #endif

	specular *= u_SpecularScale;

  #if defined(r_materialGamma)
	diffuse.rgb   = pow(diffuse.rgb,  vec3(r_materialGamma));
    #if !defined(SPECULAR_IS_METALLIC)
	specular.rgb  = pow(specular.rgb, vec3(r_materialGamma));
    #endif
  #endif

	float gloss = specular.a;
  #if defined(GLOSS_IS_ROUGHNESS)
	float roughness = gloss;
  #else
	float roughness = exp2(-3.0 * gloss);
  #endif

  #if defined(SPECULAR_IS_METALLIC)
	// diffuse is actually base color, and green of specular is metallicness
	float metallic = specular.g;

	specular.rgb = metallic * diffuse.rgb + vec3(0.04 - 0.04 * metallic);
	diffuse.rgb *= 1.0 - metallic;
  #else
	// adjust diffuse by specular reflectance, to maintain energy conservation
	diffuse.rgb *= vec3(1.0) - specular.rgb;
  #endif

	reflectance  = CalcDiffuse(diffuse.rgb, EH, NH, roughness);
  #if defined(USE_SHADOWMAP) && defined(SHADOWMAP_MODULATE)
	// bit of a hack, with modulated shadowmaps, add specular to sunlight
	H = normalize(var_PrimaryLightDir.xyz + E);
	EH = clamp(dot(E, H), 0.0, 1.0);
	NH = clamp(dot(N, H), 0.0, 1.0);
	reflectance += shadowValue * CalcSpecular(specular.rgb, NH, NL, NE, EH, roughness);
  #endif

	gl_FragColor.rgb  = lightColor   * reflectance * (attenuation * NL);
	gl_FragColor.rgb += ambientColor * (diffuse.rgb + specular.rgb);

  #if defined(USE_CUBEMAP)
	reflectance = EnvironmentBRDF(roughness, NE, specular.rgb);

	vec3 R = reflect(E, N);

	// parallax corrected cubemap (cheaper trick)
	// from http://seblagarde.wordpress.com/2012/09/29/image-based-lighting-approaches-and-parallax-corrected-cubemap/
	vec3 parallax = u_CubeMapInfo.xyz + u_CubeMapInfo.w * viewDir;

    #if defined(GLOSS_IS_ROUGHNESS)
	vec3 cubeLightColor = textureCubeLod(u_CubeMap, R + parallax, 7.0 * roughness).rgb * u_EnableTextures.w;
    #else
	vec3 cubeLightColor = textureCubeLod(u_CubeMap, R + parallax, 7.0 - gloss * 7.0).rgb * u_EnableTextures.w;
    #endif

	// normalize cubemap based on lowest mip (~diffuse)
	// multiplying cubemap values by lighting below depends on either this or the cubemap being normalized at generation
	//vec3 cubeLightDiffuse = max(textureCubeLod(u_CubeMap, N, 6.0).rgb, 0.5 / 255.0);
	//cubeLightColor /= dot(cubeLightDiffuse, vec3(0.2125, 0.7154, 0.0721));

    #if defined(r_framebufferGamma)
	cubeLightColor = pow(cubeLightColor, vec3(r_framebufferGamma));
    #endif

	// multiply cubemap values by lighting
	// not technically correct, but helps make reflections look less unnatural
	//cubeLightColor *= lightColor * (attenuation * NL) + ambientColor;

	gl_FragColor.rgb += cubeLightColor * reflectance;
  #endif

  #if defined(USE_PRIMARY_LIGHT)
	vec3 L2, H2;
	float NL2, EH2, NH2;

	L2 = var_PrimaryLightDir.xyz;

	// enable when point lights are supported as primary lights
	//sqrLightDist = dot(L2, L2);
	//L2 /= sqrt(sqrLightDist);

	NL2 = clamp(dot(N, L2), 0.0, 1.0);

	H2 = normalize(L2 + E);
	EH2 = clamp(dot(E, H2), 0.0, 1.0);
	NH2 = clamp(dot(N, H2), 0.0, 1.0);

	reflectance  = CalcDiffuse(diffuse.rgb, EH2, NH2, roughness);
	reflectance += CalcSpecular(specular.rgb, NH2, NL2, NE, EH2, roughness);

	lightColor = u_PrimaryLightColor * var_Color.rgb;

    #if defined(r_lightGamma)
	lightColor = pow(lightColor, vec3(r_lightGamma));
    #endif

    #if defined(USE_SHADOWMAP)
	lightColor *= shadowValue;
    #endif

	// enable when point lights are supported as primary lights
	//lightColor *= CalcLightAttenuation(float(u_PrimaryLightDir.w > 0.0), u_PrimaryLightDir.w / sqrLightDist);

	gl_FragColor.rgb += lightColor * reflectance * NL2;
  #endif
#else
	lightColor = var_Color.rgb;

  #if defined(USE_LIGHTMAP) 
	lightColor *= lightmapColor.rgb;
  #endif

  #if defined(r_lightGamma)
	lightColor = pow(lightColor, vec3(r_lightGamma));
  #endif

  #if defined(r_materialGamma)
	diffuse.rgb   = pow(diffuse.rgb,  vec3(r_materialGamma));
  #endif

	gl_FragColor.rgb = diffuse.rgb * lightColor;

#endif

#if defined(r_framebufferGamma)
	gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(1.0 / r_framebufferGamma));
#endif

	gl_FragColor.a = diffuse.a * var_Color.a;
}
