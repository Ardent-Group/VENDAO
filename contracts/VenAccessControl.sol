// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";


contract VenAccessControl is AccessControlDefaultAdminRules {
    bytes32 public constant NOMINATED_ADMINS = keccak256("NOMINATED_ADMINS");
    bytes32 public constant INVESTOR = keccak256("INVESTOR");
    bytes32 public constant CALLEE = keccak256("CALLEE");

    constructor(address caller, address _admin) AccessControlDefaultAdminRules(5 days, _admin) {
        _grantRole(CALLEE, caller);
        _setRoleAdmin(INVESTOR, CALLEE);

        _setRoleAdmin(NOMINATED_ADMINS, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(CALLEE, DEFAULT_ADMIN_ROLE);
    }
}