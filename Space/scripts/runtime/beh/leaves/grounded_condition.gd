@tool
extends ConditionLeaf

# SUCCESS when CharacterBody2D.is_on_floor(). Relies on the actor's
# own _physics_process having called move_and_slide this frame.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    return SUCCESS if (actor as CharacterBody2D).is_on_floor() else FAILURE
