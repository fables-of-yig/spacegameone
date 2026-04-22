@tool
extends ConditionLeaf

# Always returns SUCCESS. Useful as a placeholder when authoring a tree
# or as the true branch of a selector fallback.


func tick(_actor: Node, _blackboard: Blackboard) -> int:
    return SUCCESS
