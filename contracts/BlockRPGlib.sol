pragma solidity ^0.4.4;

library BlockRPGlib {
    enum Slots { Helm, Chest, Legs, Weapon, Shield, Boots }
    enum Stats { Attack, Defense }

    function randomNumber(uint seed, uint maxValue) constant returns (uint) {
        return(uint(sha3(block.blockhash(block.number-1), seed))%maxValue);
    }
    
    function randomNumber16(uint seed, uint16 maxValue) constant returns (uint16) {
        return uint16((uint(sha3(block.blockhash(block.number-1), seed))%maxValue));
    }
}