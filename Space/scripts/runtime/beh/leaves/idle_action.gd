@tool
extends ActionLeaf

# Stops horizontal motion on a CharacterBody2D and returns SUCCESS each
# tick. Works as the safe default when a behavior references an action
# that hasn't been registered yet.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if actor is CharacterBody2D:
        (actor as CharacterBody2D).velocity.x = 0.0
    if actor.has_method("ai_request_pose"):
        actor.call("ai_request_pose", "idle", 0.1, true, 1.0)
    return SUCCESS
