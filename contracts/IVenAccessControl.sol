// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IVenAccessControl {
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function owner() external returns(address);
    function hasRole(bytes32 role, address account) external returns(bool);
}