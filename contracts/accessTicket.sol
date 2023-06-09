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

    /**
     * @notice  . This function can only be called by Vendao
     * @dev     . Function responsible for generating dao ticket
     * @param   _investor  . address of investor
     */
    function daoPassTicket(address _investor) external returns(uint256 _newTokenId) {
        require(msg.sender == caller, "Accessibility Denied");
        _newTokenId = _tokenIds.current();
        _mint(_investor, _newTokenId);

        _tokenIds.increment();
    }

    function burnPassTicket(uint256 _tokenId) external {
        require(msg.sender == caller, "Accessibility Denied");
        _burn(_tokenId);
    }

    /**
    * @dev  . Function that holds access ticket URI
    */
    function _baseURI() internal pure override returns(string memory) {
        return "";
    }
}