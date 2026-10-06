# Equipment condition

Single-player tool wear and repair use the generic ItemInstanceService. Tools have
unique IDs and condition; transfers, saves and repairs preserve those IDs. Legacy
saved tools receive IDs on load. Accepted mining hits spend one point; cancelled
hits do not. Broken tools cannot mine. Durability bars appear in inventory slots.

Select a damaged tool in the hotbar and open inventory near a workbench to repair
it with its tier material. Repairs consume materials atomically and restore condition.
Armor can be moved to the hotbar for repair. Registered efficient, swift and reinforced
modifier IDs affect effective stats; an acquisition/enchantment interface is pending.

Run tests/EquipmentConditionSmoke.tscn for identity, wear, repair and migration checks.
