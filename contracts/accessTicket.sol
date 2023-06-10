// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./IVenAccessControl.sol";


contract VenAccessTicket is ERC721 {
    bytes32 public constant CALLEE = keccak256("CALLEE");

    using Counters for Counters.Counter;

    /**===================================
    *               Events
    =====================================*/
    event newCaller(address, address);

    /*====================================
    **           STATE VARIBLES
    =====================================*/
    Counters.Counter private _tokenIds;
    IVenAccessControl public VenAccessControl;

    constructor(IVenAccessControl _accessControl) ERC721("Ven DAO", "VEN"){
        VenAccessControl = _accessControl;
    }

    /**
     * @notice  . This function can only be called by Vendao
     * @dev     . Function responsible for generating dao ticket
     * @param   _investor  . address of investor
     */
    function daoPassTicket(address _investor) external returns(uint256 _newTokenId) {
        require(VenAccessControl.hasRole(CALLEE, msg.sender), "Accessibility Denied");
        _newTokenId = _tokenIds.current();
        _mint(_investor, _newTokenId);

        _tokenIds.increment();
    }

    function burnPassTicket(uint256 _tokenId) external {
        require(VenAccessControl.hasRole(CALLEE, msg.sender), "Accessibility Denied");
        _burn(_tokenId);
    }

    /**
    * @dev  . Function that holds access ticket URI
    */
    function _baseURI() internal pure override returns(string memory) {
        return "";
    }
}