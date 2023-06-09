// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";


contract VenAccessControl is AccessControlDefaultAdminRules {
    bytes32 public constant NOMINATED_ADMINS = keccak256("NOMINATED_ADMINS");
    bytes32 public constant INVESTOR = keccak256("INVESTOR");
    bytes32 public constant ADMIN = keccak256("ADMIN");

    constructor(address caller, address _admin) AccessControlDefaultAdminRules(5 days, caller) {
        _setRoleAdmin(NOMINATED_ADMINS, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(INVESTOR, DEFAULT_ADMIN_ROLE);
        _grantRole(ADMIN, _admin);
    }
}