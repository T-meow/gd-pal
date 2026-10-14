class_name PalInstanceManager
extends Node

signal instance_added(instance: PalPetInstance)
signal instance_removed(instance_id: String)

const PET_SCENE: PackedScene = preload("res://scenes/characters/pet_instance.tscn")
const MAX_PREVIEW_INSTANCES: int = 4
var instances: Dictionary = {}
var _next_id: int = 1


func create_pet(visual_id: String, surface_parent: Node, saved_profile: PalProfile = null) -> PalPetInstance:
	if PalUi.is_mobile():
		visual_id = "sprite2d"
	if instances.size() >= MAX_PREVIEW_INSTANCES or not PalPetInstance.PRESENTERS.has(visual_id):
		return null
	var pet := PET_SCENE.instantiate() as PalPetInstance
	pet.instance_id = "pet_%d" % _next_id
	pet.name = pet.instance_id
	pet.profile = saved_profile if saved_profile != null else PalProfile.new()
	if pet.profile.profile_id.is_empty():
		pet.profile.profile_id = Crypto.new().generate_random_bytes(16).hex_encode()
	if saved_profile == null:
		pet.profile.display_name = PalProfile.DEFAULT_NAME if _next_id == 1 else PalProfile.DEFAULT_NAME + " %d" % _next_id
	pet.profile.visual_id = visual_id
	_next_id += 1
	instances[pet.instance_id] = pet
	surface_parent.add_child(pet)
	instance_added.emit(pet)
	return pet


func remove_pet(instance_id: String) -> bool:
	if not instances.has(instance_id):
		return false
	var pet: PalPetInstance = instances[instance_id]
	instances.erase(instance_id)
	pet.queue_free()
	instance_removed.emit(instance_id)
	return true
