pragma solidity ^0.4.15;

import "./BlockRPGlib.sol";

/**
Standard Ownable contract
 */
contract Ownable {
    address public owner;
   
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


    /**
    * @dev The Ownable constructor sets the original `owner` of the contract to the sender
    * account.
    */
    function Ownable() {
        owner = msg.sender;
    }


    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }


    /**
    * @dev Allows the current owner to transfer control of the contract to a newOwner.
    * @param newOwner The address to transfer ownership to.
    */
    function transferOwnership(address newOwner) onlyOwner public {
        require(newOwner != address(0));
        OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

/**
Base contract used by the contracts instantiated by the BlockRPG contract
Contains a reference to the main game contract
 */
contract GameObject {
    address public owner;
    BlockRPG game;

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    /**
    * @dev Throws if called by any account other than the game.
    */
    modifier onlyGame() {
        require(msg.sender == address(game));
        _;
    }
    
    /**
    * @dev Throws if called by any account other than the owner or game.
    */
    modifier onlyGameOrOwner() {
        require(msg.sender == owner || msg.sender == address(game));
        _;
    }

    function GameObject(BlockRPG _game, address _owner) {
        owner = _owner;
        game = _game;
    }
}

/**
Base contract for Characters and Mobs
 */
contract Actor is GameObject {
    uint24 public attack;
    uint24 public defense;
    uint8 public level = 1;
}

/**
Character contract used by players to interact with the game
 */
contract Character is Actor {
    // List of itemIds that are equipped
    uint40[6] public equipmentIds;
    // Inventory list
    uint40[] inventoryIds;
    // Current expereince
    uint public exp;
    // Player name
    string public name;

    function Character(BlockRPG _game, address _owner) GameObject(_game, _owner) {
        calculateStats();
    }

    /**
    * @dev Sets the character name
    * @param _name The new name.
    */
    function setName(string _name) {
        name = _name;
    }

    /**
    * @dev Calculate the character's stats based on their level and equipment
    */
    function calculateStats() internal {
        attack = uint24(10 + game.itemsStatSum(equipmentIds, BlockRPGlib.Stats.Attack) + (level * 2));
        defense = uint24(game.itemsStatSum(equipmentIds, BlockRPGlib.Stats.Defense) + (level));
    }

    /**
    * @dev Award experience (called by game contract)
    * @param amount Amount of exp to add
    */
    function awardExperience(uint amount) onlyGame {
        exp += amount;
    }

    /**
    * @dev Length of the player's inventory
    */
    function inventoryCount() constant onlyOwner returns(uint) {
        return inventoryIds.length;
    }

    /**
    * @dev Returns the itemId in that inventory slot
    */
    function inventory(uint index) constant onlyOwner returns(uint40) {
        return inventoryIds[index];
    }

    /**
    * @dev Equip an item from the inventory
    * @param itemId itemId of the item to equip
    */
    function equipItem(uint40 itemId) onlyOwner {
        var (itemOwner, itemSlot) = game.getItemDetails(itemId);
        require(itemOwner == this);
        equipmentIds[uint(itemSlot)] = itemId;
        calculateStats();
    }

    /**
    * @dev Add an item to the player's inventory
    * @param itemId itemId to add
    */
	function addItemToInventory(uint40 itemId) onlyGame {
		inventoryIds.push(itemId);
	}
	
    /**
    * @dev Set the player's level
    * @param _level New level
    */
	function setLevel(uint8 _level) onlyGame {
        level = _level;
        calculateStats();
    }
}

/**
Mob contract. Spawned from zones and contain loot
 */
contract Mob is Actor {    
    // Used for the PRNG
    uint randomSeed;
    // The date the mob was killed on
    uint public killedOn;
    // The block the killed mob will respawn on
    uint public respawnBlockNumber;
    // The character that killed this mob
    Character public killedBy;
    // List of possible loot itemIds
    uint40[3] loot;
    
    /**
    Event generated every time a mob is attacked by a player
    */
    event MobAttacked (
        address indexed attacker,
        uint attackRoll,
        uint defenseRoll,
        uint40[3] lootFound
    );

    function Mob(BlockRPG _game, address _owner, uint8 _level) GameObject(_game, _owner) {
        setLevel(_level);
    }

    /**
    * @dev Attack this mob. Intended to be called from an address that has an associated character.
    If the mob is killed, loot is rolled on and awarded to the player
    */
	function doAttack() {
	    require(isAlive());
        var character = game.getCharacter(msg.sender);
	    require(character != address(0x0));
        
        // Max attack is the player's attack minus the mob's defense
        var maxAttack = character.attack() - defense;
        if (maxAttack < 1)
            maxAttack = 1;
            
        // Max defense is the mob's attack minus the player's defense
        var maxDefense = attack - character.defense();
        if (maxDefense < 1)
            maxDefense = 1;
            
        // Get random rolls based on the attacker and defenders strength
		var attackRoll = BlockRPGlib.randomNumber(randomSeed++, maxAttack);
		var defenseRoll = BlockRPGlib.randomNumber(randomSeed++, maxDefense);
		
        uint40[3] memory lootFound;
		if (attackRoll > defenseRoll) {
            // Attacker won
            lootFound = Zone(owner).onMobKilled(character);
            killedOn = block.number;
            killedBy = character;
            respawnBlockNumber = block.number + 50 + (level * 5) + BlockRPGlib.randomNumber(randomSeed, 10);
		}

        // Broadcast event
        MobAttacked(character, attackRoll, defenseRoll, lootFound);
	}
	
    /**
    * @dev Set the mob's level
    * @param _level New level
    */
	function setLevel(uint8 _level) onlyGameOrOwner {
        level = _level;
        calculateStats();
    }
    
    /**
    * @dev Calculate the stats
    */
	function calculateStats() internal {
        attack = 1 + (level * 5);
        defense = (level * 4);
    }
	
    /**
    * @dev Set the loot that can drop on death
    * @param lootIndex The index in the loot array to set
    * @param itemId Loot's itemId
    */
	function setLoot(uint lootIndex, uint40 itemId) onlyGameOrOwner {
	    loot[lootIndex] = itemId;
	}

    /**
    * @dev Gets the possible loot itemIds
    */
    function getLoot() constant returns (uint40[3] lootIds) {
		lootIds = loot;
    }
	
    /**
    * @dev Remove loot from the mob
    * @param lootIndex Index in the loot array to remove
    */
	function removeLoot(uint lootIndex) onlyGame {
		delete loot[lootIndex];
	}

    /**
    * @dev Returns the mob's current alive status
    */
    function isAlive() constant returns (bool) {
        if (killedOn == 0)
            return true;

        return block.number >= respawnBlockNumber;
    }
}

/**
Zone contract. Zones contain mobs
 */
contract Zone is GameObject {
    // List of mobs spawned in this zone
    Mob[] mobs;
    // Map of valid mob addresses 
    mapping (address => bool) mobMap;
    // PRNG seed
    uint randomSeed;
    // Zone level. Used to set spawned mob levels
    uint8 public mobLevels;

    function Zone(BlockRPG _game, address _owner, uint8 _mobLevels) GameObject(_game, _owner) {
        mobLevels = _mobLevels;
        game = _game;
    }
    
    /**
    * @dev Spawns mobs
    * @param count Number of mobs to spawn (1 to 5)
    */
    function spawnMobs(uint8 count) onlyOwner {
        require(count <= 5 && count > 0);
        require((mobs.length + count) < 30);
        
        for (uint index = 0; index < count; index++) {
            var mob = new Mob(game, this, mobLevels);
            mobs.push(mob);
            mobMap[mob] = true;
        }
    }
    
    /**
    * @dev Called when a mob has been killed
    * @param killedBy The character that killed this mob
    * @return loot Loot found
    */
    function onMobKilled(Character killedBy) returns(uint40[3] loot) {
        var mob = mobMap[msg.sender];
        require(mob);

        return game.onMobKilled(Mob(msg.sender), killedBy);
    }
    
    /**
    * @dev Create the loot on the specific mob
    * @param mob The mob to spawn loot on
    */
    function createLoot(Mob mob) onlyOwner {
        var loot = mob.getLoot();
        for (uint8 index2 = 0; index2 < 3; index2++) {
            if (loot[index2] == 0) {
                uint40 itemId = game.createItem(mobLevels, randomSlot());
                mob.setLoot(index2, itemId);
            }
        }
    }
    
    /**
    * @dev Returns the currently spawned mobs
    */
    function mobList() constant returns(Mob[]) {
        return mobs;
    }
    
    /**
    * @dev Returns a random equipment slot
    */
    function randomSlot() private returns(BlockRPGlib.Slots) {
        return BlockRPGlib.Slots(BlockRPGlib.randomNumber(randomSeed++, 6));
    }
}

/**
The main game contract
 */
contract BlockRPG is Ownable {

    // Map addresses to characters
	mapping (address => Character) characters;
    // Map creator address to Zone
	mapping (address => Zone) zoneMap;
    // Map zone address to true if it exists
	mapping (address => bool) zones;
    // List of zones
    Zone[] public zoneList;
    // List of characters
    Character[] public characterList;
    // Maps itemIds to the actual item
	mapping (uint40 => GameItem) items;
    // Persistant itemId counter    
    uint40 currentItemId = 1;
    // Current random seed
	uint randomSeed;
    
    // Item quality. Determines the power of an item
	enum ItemQuality {
		Common, Rare, Epic, Legendary, GodLike
	}
    
    // Item struct
	struct GameItem {
		uint40 id;
        uint16 attack;
        uint16 defense;
		uint16 dropRate;
        uint8 set;
		ItemQuality quality;
        BlockRPGlib.Slots slot;
        Character owner;
    }

    // New character event
    event NewCharacter(address indexed senderAddreess, address characterAddress);
    // New zone event
    event NewZone(address indexed senderAddreess, address zoneAddress);
    
    /**
    * @dev Allow only from zones
    */
    modifier onlyZone() {
        require(zones[msg.sender]);
        _;
    }

	function BlockRPG() {
	}

    /**
    * @dev Create a new character contract. Message sender becomes the owner
    */
	function createCharacter() {
		var existing = characters[msg.sender];
		require(existing == address(0x0));

		var characterAddress = new Character(this, msg.sender);
		characters[msg.sender] = Character(characterAddress);
        characterList.push(characterAddress);

        NewCharacter(msg.sender, characterAddress);
	}

    /**
    * @dev Returns the sum of a specific stat from an array of itemIds
    * @param itemIds List of equipment itemIds
    * @param stat Stat to get a sum of
    */
	function itemsStatSum(uint40[6] itemIds, BlockRPGlib.Stats stat) constant returns (uint32) {
		uint32 total = 0;
		for (uint8 index = 0; index < 6; index++) {
			uint40 itemId = itemIds[index];
			if (itemId == 0)
				continue;

			GameItem memory item = items[itemId];

			if (stat == BlockRPGlib.Stats.Attack)
				total += item.attack;
			else if (stat == BlockRPGlib.Stats.Defense)
				total += item.defense;
		}

		return total;
	}

    /**
    * @dev Get the basic item info for an item
    * @param itemId ID of the item
    */
	function getItemDetails(uint40 itemId) constant returns(Character owner, BlockRPGlib.Slots slot) {
		GameItem memory item = items[itemId];
		owner = item.owner;
		slot = item.slot;
	}

    /**
    * @dev Create an item to be used for loot
    * @param itemLevel Level of the item
    * @param slot Slot of the item
    * @return itemId Newly created itemId
    */
	function createItem(uint8 itemLevel, BlockRPGlib.Slots slot) onlyZone returns(uint40 itemId) {
        // Do a random roll to determine our quality
		var qualityRoll = BlockRPGlib.randomNumber(randomSeed++, 1000);
		ItemQuality quality = ItemQuality.Common;

		if (qualityRoll > 980)
			quality = ItemQuality.GodLike;
		else if (qualityRoll > 950)
			quality = ItemQuality.Legendary;
		else if (qualityRoll > 900)
			quality = ItemQuality.Epic;
		else if (qualityRoll > 600)
			quality = ItemQuality.Rare;

        // The stat mods based on the quality
		uint atkMod = 1 + uint(quality);
		uint defMod = 1 + uint(quality);

        // Flat drop rate based on quality
		uint16 dropRate = 900 - (uint16(quality) * 200);

        // Max possible attack/defense
        var maxAtk = ((itemLevel * itemLevel) + atkMod) * atkMod;
        var maxDef = ((itemLevel * itemLevel) + atkMod) * defMod;

		var item = GameItem(0,
			uint16(1 + BlockRPGlib.randomNumber(randomSeed++, maxAtk)), // attack
			uint16(1 + BlockRPGlib.randomNumber(randomSeed++, maxDef)), // defense
			dropRate, // Droprate
            uint8(BlockRPGlib.randomNumber(randomSeed++, 255)), // Set
			quality, // Quality
			slot, // slot
			Character(address(0x0)) // owner
		);

		itemId = addItem(item);
	}

    /**
    * @dev Add an item to the game
    * @param item Item to be added
    * @return itemId Inserted itemId
    */
	function addItem(GameItem item) internal returns(uint40 itemId) {
		item.id = currentItemId++;
        items[item.id] = item;
        return item.id;
	}

    /**
    * @dev Get an item
    * @param itemId ItemId of the item
    */
    function getItem(uint40 itemId) constant returns (uint16 attack, uint16 defense, uint16 dropRate, uint8 set, ItemQuality quality, BlockRPGlib.Slots slot, Character owner) {
        GameItem memory item = items[itemId];
        attack = item.attack;
        defense = item.defense;
        dropRate = item.dropRate;
        set = item.set;
        quality = item.quality;
        slot = item.slot;
        owner = item.owner;
    }

    /**
    * @dev Number of created characters
    */
    function characterCount() constant returns(uint) {
        return characterList.length;
    }

    /**
    * @dev Number of created zones
    */
    function zoneCount() constant returns(uint) {
        return zoneList.length;
    }

    /**
    * @dev Create a new zone. Sender becomes the owner
    */
	function deployZone() {
		var existing = zoneMap[msg.sender];
		require(existing == address(0x0));

		Zone zone = new Zone(this, msg.sender, 1);
		zones[zone] = true;
        zoneMap[msg.sender] = zone;
        zoneList.push(zone);

        NewZone(msg.sender, zone);
	}

    /**
    * @dev Get character owned by the address
    * @param from Address of character's owner
    */
	function getCharacter(address from) constant returns(Character) {
		return characters[from];
	}

    /**
    * @dev Get zone owned by the address
    * @param from Address of zone's owner
    */
	function getZone(address from) constant returns(Zone) {
		return zoneMap[from];
	}

    /**
    * @dev Called when a mob is killed
    * @param mob Mob that was killed
    * @param killedBy Character that killed the mob
    * @return lootFound Array of itemIds found. Values of 0 mean no loot
    */
	function onMobKilled(Mob mob, Character killedBy) onlyZone returns(uint40[3] lootFound) {
        // Award exp
		killedBy.awardExperience(mob.level() * 10);
		
        // Get possible loot
		uint40[3] memory loot = mob.getLoot();

        // Loop through possible loot and roll on it
		for (uint8 index = 0; index < loot.length; index++) {
			uint40 itemId = loot[index];
			if (itemId == 0)
				continue;
				
			var item = items[itemId];
			var roll = BlockRPGlib.randomNumber(randomSeed++, 1000);

			if (roll <= item.dropRate) {
				// Award the item
				mob.removeLoot(index);
                item.owner = killedBy;
                killedBy.addItemToInventory(item.id);
				lootFound[index] = itemId;
			}
		}
	}
}
