@tool
extends ConditionLeaf

# Returns SUCCESS when the actor is pressed against a wall, per Godot's
# CharacterBody2D.is_on_wall(). Relies on the actor's own _physics_process
# to call move_and_slide each frame, so the flag stays fresh.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    return SUCCESS if (actor as CharacterBody2D).is_on_wall() else FAILURE
