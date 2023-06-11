// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IVenAccessTicket {
    function daoPassTicket(address _investor) external returns(uint256 _newTokenId);
    function burnPassTicket(uint256 _tokenId) external;
}
