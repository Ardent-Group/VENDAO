// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

struct Contestant {
    string name;
    uint128 voteCount;
    address participant;
    uint8 Id;
}

interface IVoting {
    function setContestant(Contestant memory _contestant, uint40 _voteTime) external;
    function resetContestant() external;
}