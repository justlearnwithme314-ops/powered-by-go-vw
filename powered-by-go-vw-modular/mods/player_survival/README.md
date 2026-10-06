# Survival and combat

Single-player players receive 20 health, oxygen, fall damage, drowning, hunger-based
healing, starvation and poison damage. Hand-craft bandages from leaves; right-click
one to heal while injured. Workbench recipes provide iron and diamond armor.
Equipped armor reduces physical/projectile damage and loses condition when hit.

Primary input attacks nearby physics entities that expose DamageReceiver, with tool
condition and knockback. This provides a combat interface; enemy AI is not included.
Death disables actions and opens a respawn screen. Inventory is retained in this
release. Respawn restores health/oxygen and grants brief damage protection.

Health, hunger and death state persist in the local world snapshot. Shared combat,
server damage authority, death loot and custom checkpoints are future work.
Run tests/SurvivalCombatSmoke.tscn and tests/ProgressionWorldSmoke.tscn.
