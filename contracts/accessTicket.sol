// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VenAccessTicket is ERC721, Ownable {
    using Counters for Counters.Counter;

    /**===================================
    *               Events
    =====================================*/
    event newCaller(address, address);

    /*====================================
    **           STATE VARIBLES
    =====================================*/
    Counters.Counter private _tokenIds;
    address caller;

    constructor(address _caller) ERC721("Ven DAO", "Ven") {
        caller = _caller;

        
    }

    function changeCaller(address _caller) external onlyOwner {
        address oldCaller = caller;
        caller = _caller;

        emit newCaller(oldCaller, caller);
    }

    function _daoPassTicket(address _investor) external returns(uint256 _newTokenId) {
        require(msg.sender == caller, "Accessibility Denied");
        _newTokenId = _tokenIds.current();
        _mint(_investor, _newTokenId);

        _tokenIds.increment();
    }
}