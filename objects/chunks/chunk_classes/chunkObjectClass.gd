extends Resource

class_name ChunkObject

@export var object_name : String
@export var object_types : Dictionary[String,chunkObjectTypeChance]
@export var max_single_objects_per_chunk: int = 32
@export var empty_chunk_chance: float = 20.0# 1-100%
@export var object_size_offset: float = 1.0 # default = 1.0 or < 1
@export var chance_at_height: Dictionary[Array, float] = {[0.0,0.0]:100.0}
@export var procent_in_forest: = 0.0
@export var multimesh_height: = 0.0 # Висота мультимеша. Потрібно для LOD. Для стандартного lod_bias достатньо 0
