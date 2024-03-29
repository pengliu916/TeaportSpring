Texture1D txRandom : register( t0 );
Texture2D txSpark : register( t1 );
SamplerState samGeneral : register( s0 );

#define LAUNCHER		0
#define WATERDROP		1

cbuffer cbAllInOne : register( b0 )
{
	matrix mWorldViewProj;
	matrix mWorldView;
	matrix mInvWorldView;
	matrix mTeapot;
	matrix mSphere;
	float4 vFrameGravity;

	float fGlobalTime;
	float fElapsedTime;
	float fFireInterval;
	float fMaxDrops;
	
	float fDropInitVel;
	float fDropLife;
	float fDropLengthFactor;
	float fSphereRadius;

	float4 vSpherePos;

	float fGroundHeight;

};

struct VS_Update_INPUT
{
	float3 pos : POSITION;
	float3 vel : NORMAL;
	float Timer : TIMER;
	uint Type : TYPE;
};

VS_Update_INPUT AdvanceVS( VS_Update_INPUT input)
{
	return input;
}
;
float3 RandomDir( float offset )
{
	float tCoord = (fGlobalTime + offset ) / 100.0;
	return txRandom.SampleLevel( samGeneral, tCoord, 0 ).xyz;
}

void GSGenericHandler( VS_Update_INPUT input, uint primID : SV_PrimitiveID, inout PointStream<VS_Update_INPUT> outputStream )
{
	if( input.Timer>=0 ){
		input.pos += input.vel * fElapsedTime;
		float dPS = distance( input.pos, vSpherePos.xyz );
		if( dPS < fSphereRadius ){
			float3 norm = input.pos - vSpherePos.xyz;
			float rdot = dot( norm, -input.vel );
			float vlength = length(input.vel);
			float3 vReflect = normalize( 2 * rdot * norm + input.vel );
			input.vel = vlength * vReflect;
			input.pos += ( fSphereRadius - dPS ) * 1.01 * norm;
		}
		if( input.pos.y <= fGroundHeight && abs(input.pos.x) <= 5 && abs(input.pos.z)<=5){
			input.vel.y*=-0.4;
			float vlength = length(input.vel);
			input.vel += normalize( RandomDir( input.Type + primID ) )*0.15*vlength;
			input.pos.y = fGroundHeight + 0.003;
		}
		input.vel += vFrameGravity.xyz;
		input.Timer -= fElapsedTime;

		outputStream.Append( input );
	}
}

void GSLauncherHandler( VS_Update_INPUT input, uint primID : SV_PrimitiveID, inout PointStream<VS_Update_INPUT> outputStream )
{
	if( input.Timer <= 0 ){
		for( int i = 0; i < fMaxDrops; i++ ){
		float3 vRandom = normalize( RandomDir( input.Type + primID + i) );
		VS_Update_INPUT output;
		output.pos = mul(float4(input.pos,1), mTeapot).xyz + input.vel * fElapsedTime;
		output.vel = mul(input.vel, mTeapot) + vRandom *0.2;
		output.Timer = fDropLife + vRandom.x * 0.5;
		output.Type = WATERDROP;
		outputStream.Append( output );
		input.Timer = fFireInterval + vRandom.y * 0.03;
		}
	}else{
		input.Timer -= fElapsedTime;
	}
	outputStream.Append( input );
}



[maxvertexcount(128)]
void AdvanceGS( point VS_Update_INPUT input[1], uint primID : SV_PrimitiveID, inout PointStream<VS_Update_INPUT> outputStream )
{
	if( input[0].Type == LAUNCHER )	GSLauncherHandler( input[0], primID, outputStream );
	else GSGenericHandler( input[0], primID, outputStream );
}




struct GS_Render_INPUT
{
	float3 pos : POSITION;
	float4 color : COLOR0;
	float radius : RADIUS;
};

GS_Render_INPUT RenderVS( VS_Update_INPUT input )
{
	GS_Render_INPUT output = ( GS_Render_INPUT )0;
	output.pos = input.pos;
	output.radius = 0.1;

	float3 vRandom=normalize( RandomDir( input.pos.y*8 ));
	float initAlpha = abs( vRandom.x );


	if( input.Type == LAUNCHER ){
		
	}else {
		output.color = float4(0.4228,0.6515,0.8904,initAlpha);
		output.color.rgb *= ( 1.0f - input.Timer / fDropLife );
		output.color.a *= ( input.Timer / fDropLife );
		//output.color.a = 1.0f - output.color.a;
	}
	return output;
}

struct PS_Render_INPUT
{
	float4 pos : SV_POSITION;
	float2 tex : TEXTURE0;
	float4 color : COLOR0;
};

cbuffer cbImmutable
{
	static const float3 positions[4] =
	{
		float3( -1, 1, 0 ),
		float3( 1, 1, 0 ),
		float3( -1, -1, 0 ),
		float3( 1, -1, 0 ),
	};
	static const float2 texcoords[4] = 
	{ 
		float2(0,1), 
		float2(1,1),
		float2(0,0),
		float2(1,0),
	};
};


[maxvertexcount(4)]
void RenderGS( point GS_Render_INPUT input[1], inout TriangleStream<PS_Render_INPUT> outputStream )
{
	PS_Render_INPUT output;
	for( int i = 0; i < 4; i++ ){
		float3 position = positions[i] * input[0].radius;
		position = mul( position, (float3x3)mInvWorldView ) + input[0].pos;
		output.pos = mul( float4( position, 1.0 ), mWorldViewProj );

		output.color = input[0].color;
		output.tex = texcoords[i];
		outputStream.Append( output );
	}
	outputStream.RestartStrip();
}

float4 RenderPS( PS_Render_INPUT input ) : SV_Target
{
	return txSpark.Sample( samGeneral, input.tex ) * input.color;
}


struct VS_INPUT
{
	float4 vPosition	: POSITION;
	float3 vNormal		: NORMAL;
	float2 vTexcoord	: TEXCOORD0;
};

struct VS_OUTPUT
{
   float4 Pos    : SV_POSITION;
   float3 Norm   : NORMAL;
   float3 View   : TEXCOORD0;
   float3 lPos  : TEXCOORD1;
};

//--------------------------------------------------------------------------------------
// Vertex Shader
//--------------------------------------------------------------------------------------

static const float4 ambient = float4( 0.9255, 0.9380, 0.9380, 1 );
static const float4 diffuse = float4( 0.8392, 0.8623, 0.8904, 1 );
static const float4 specular = float4( 1.0000, 0.9567, 0.6704, 1 );
static const float4 ks = float4( 0.08, 0.44, 0.82, 16 );
static const float3 lightPos = float3( 10,10,-20); 


VS_OUTPUT TeapotVS( VS_INPUT Input )
{
	VS_OUTPUT Output;
	
	float4 movedPos = mul( Input.vPosition, mTeapot );
	Output.Pos = mul( movedPos, mWorldViewProj );
	Output.lPos = mul( movedPos, mWorldView );
	Output.View = -normalize( Output.lPos );
	float3 movedNormal = mul( Input.vNormal, (float3x3)mTeapot );
	Output.Norm = mul( movedNormal, (float3x3)mWorldView );
	
	return Output;
}

VS_OUTPUT SphereVS( VS_INPUT Input )
{
	VS_OUTPUT Output;
	
	float4 movedPos = mul( Input.vPosition * float4( 2.3*fSphereRadius,2.3*fSphereRadius,2.3*fSphereRadius,1), mSphere );
	Output.Pos = mul( movedPos, mWorldViewProj );
	Output.lPos = mul( movedPos, mWorldView );
	Output.View = -normalize( Output.lPos );
	float3 movedNormal = mul( Input.vNormal, (float3x3)mSphere );
	Output.Norm = mul( movedNormal, (float3x3)mWorldView );
	
	return Output;
}

VS_Update_INPUT GroundVS( VS_Update_INPUT Input )
{
	return Input;
}

[maxvertexcount(4)]
void GroundGS(point VS_Update_INPUT particles[1], inout TriangleStream<VS_OUTPUT> triStream)
{
   VS_OUTPUT output;
   float3 pos;
   float3 Normal = float3( 0, 1, 0 );
	pos = float3( -1.0f, fGroundHeight, 1.0f ) * float3( 5, 1, 5 );
	output.Pos = mul( float4( pos, 1.0f), mWorldViewProj );
	output.lPos = mul( pos, (float3x3)mWorldView );
	output.View = -normalize( output.lPos );
	output.Norm = mul( Normal, (float3x3)mWorldView );
	triStream.Append(output);

	pos = float3( 1.0f, fGroundHeight, 1.0f ) * float3( 5, 1, 5 );
	output.Pos = mul( float4( pos, 1.0f), mWorldViewProj );
	output.lPos = mul( pos, (float3x3)mWorldView );
	output.View = -normalize( output.lPos );
	output.Norm = mul( Normal, (float3x3)mWorldView );
	triStream.Append(output);

	pos = float3( -1.0f, fGroundHeight, -1.0f ) * float3( 5, 1, 5 );
	output.Pos = mul( float4( pos, 1.0f), mWorldViewProj );
	output.lPos = mul( pos, (float3x3)mWorldView );
	output.View = -normalize( output.lPos );
	output.Norm = mul( Normal, (float3x3)mWorldView );
	triStream.Append(output);

	pos = float3( 1.0f, fGroundHeight, -1.0f ) * float3( 5, 1, 5 );
	output.Pos = mul( float4( pos, 1.0f), mWorldViewProj );
	output.lPos = mul( pos, (float3x3)mWorldView );
	output.View = -normalize( output.lPos );
	output.Norm = mul( Normal, (float3x3)mWorldView );
	triStream.Append(output);
}

struct PS_INPUT
{
	float3 Normal	: NORMAL;
	float3 View		: TEXCOORD0;
	float3 lPos		: TEXCOORD1;
};


float4 MeshPS( VS_OUTPUT Input ) : SV_TARGET
{
	float3 light = normalize( lightPos - Input.lPos);
	float rdot =  dot( Input.Norm, light );
	float3 vReflect = normalize( 2 * rdot * Input.Norm - light );
	float4 AmbientColor = ambient * ks.x;
	float4 DiffuseColor = diffuse * ks.y * max( 0, rdot );
	float4 SpecularColor = specular * ks.z * pow( max( 0, dot( vReflect, Input.View )), ks.w );
	float4 color = AmbientColor + DiffuseColor + SpecularColor;
	color.a = 1;
	return color;
}


