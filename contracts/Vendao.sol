// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Vendao is ERC721, AccessControlDefaultAdminRules{
    bytes32 public constant NOMINATED_ADMINS = keccak256("NOMINATED_ADMINS");
    bytes32 public constant INVESTOR = keccak256("INVESTOR");
    using Counters for Counters.Counter;

    /**===================================
     *            Custom Error
    =====================================*/
    error notAdmin(string);
    error lowerThanFee(string);
    error noElection(string);
    error exceedLimit(string);

    /**===================================
     *            EVENTS
    =====================================*/

    /*====================================
    **           STATE VARIBLES
    =====================================*/
    Counters.Counter private _tokenIds;
    uint128 acceptanceFee;
    Contestant[10] public contestant;
    uint40 voteTime;

    mapping(address => uint8) public voteLimit; // Investors vote limit;

    struct Contestant {
        string name;
        uint128 voteCount;
        address participant;
        uint8 Id;
    }

    struct Project {
        string _urlToStorage;
        uint40 proposedTime;
    }


    constructor() ERC721("Vendao", "Ven") AccessControlDefaultAdminRules(5 days, msg.sender){
        _setRoleAdmin(NOMINATED_ADMINS, DEFAULT_ADMIN_ROLE);
    }

    /**
     * @dev     . function responsible to set acceptance fee
     * @param   _acceptance  . New acceptance fee to be set
     */
    function setAcceptanceFee(uint128 _acceptance) external {
        if(msg.sender != owner()) revert notAdmin("VENDAO: Only admin can alter change");
        acceptanceFee = _acceptance;
    }

    /**
     * @dev . Function responsible for joining Vendao
     */
    function joinDAO() external payable returns (uint256 _newTokenId) {
        if(msg.value < acceptanceFee) revert lowerThanFee("VENDAO: fee is less than the required fee");
        _grantRole(INVESTOR, msg.sender);
        _newTokenId = _daoPassTicket(msg.sender);
        voteLimit[msg.sender] = 0;
    }

    function leaveDAO() external payable onlyRole(INVESTOR) {
        _revokeRole(INVESTOR, msg.sender);
        (bool success, ) = payable(msg.sender).call{value: (acceptanceFee / 2)}("");

        require(success, "Transaction Unsuccessful");
    }

    // ================ VOTING ARENA ===================

    function setContestant(Contestant[10] memory _contestant, uint40 _voteTime) external {
        if(msg.sender != owner()) revert notAdmin("VENDAO: Only admin can alter change");
        contestant = _contestant;
        voteTime = _voteTime;
    }

    function resetVoteLimit() external onlyRole(INVESTOR) {
        if(block.timestamp > voteTime) revert noElection("VENDAO: No upcoming election");
        require(voteLimit[msg.sender] > 0, "Eligible to vote");
        voteLimit[msg.sender] = 0;
    }

    function voteAdmin(uint8 _id) public onlyRole(INVESTOR){
        if(voteLimit[msg.sender] < 4) revert exceedLimit("Exceed Voting limit");
        contestant[_id].voteCount += 1;
        voteLimit[msg.sender] += 1;
    }

    function top5Nominees() public view returns(Contestant[] memory) {
        Contestant[10] memory _contestant = contestant;
        Contestant[] memory nominees = new Contestant[](5);

        Contestant memory max;
        uint8 index;
        for(uint8 i = 0; i < 5; i++){
            max = nominees[0];
            index = 0;

            for(uint8 j = 0; j < _contestant.length; j++){
                if(max.voteCount < _contestant[j].voteCount){
                    max.voteCount = _contestant[j].voteCount;
                    index = j;
                }
            }
            nominees[i] = max;
            delete _contestant[index];
        }
        return nominees;
    }

    function proposeProject() public view {

    }

    /**
    * @dev     . Function that holds access ticket URI
    */
    function _baseURI() internal pure override returns(string memory) {
        return "";
    }

    /**
     * @dev     . Function responsible for generating dao ticket
     * @param   _investor  . address of investor
     */
    function _daoPassTicket(address _investor) internal returns(uint256 _newTokenId){
        _newTokenId = _tokenIds.current();
        _mint(_investor, _newTokenId);

        _tokenIds.increment();
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControlDefaultAdminRules) returns (bool){
        return super.supportsInterface(interfaceId);
    }
}