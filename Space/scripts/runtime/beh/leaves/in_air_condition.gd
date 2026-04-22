@tool
extends ConditionLeaf

# SUCCESS when the actor is NOT on the floor. Mirror of
# grounded_condition — exists as a named preset so authors don't have
# to wrap grounded in an inverter.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    return SUCCESS if not (actor as CharacterBody2D).is_on_floor() else FAILURE
