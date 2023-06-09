// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vendao is ERC721, AccessControlDefaultAdminRules, ReentrancyGuard{
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
    error approved(string);
    error timeUp(string);

    /**===================================
     *            EVENTS
    =====================================*/

    /*====================================
    **           STATE VARIBLES
    =====================================*/
    Counters.Counter private _tokenIds;
    uint128 acceptanceFee;
    Contestant[] public contestant;
    uint40 voteTime;
    mapping(address => uint8) public voteLimit; // Investors vote limit;
    mapping(address => mapping(uint48 => bool)) nomineesApproved;
    uint256 DAO_FTM_BALANCE;
    mapping(address => mapping(uint48 => uint256)) investorFund;
    mapping(address => uint256) investorsId;
    Project[] public projectProposals; // List of project proposals
    Invest[] public proposalsToInvest; // List of proposals to invest in
    FundedProject[] public projectFunded; // List of project funded

    struct Contestant {
        string name;
        uint128 voteCount;
        address participant;
        uint8 Id;
    }

    struct Project {
        string urlToStorage;
        uint40 proposalValidity; // The minimum waiting time before approval or rejection
        address proposalCreator;
        uint48 proposalId;
        uint8 approvalCount;
        Status status;
        uint256 fundingRequest;  // Request in dollar
        uint256 equityOffering;  // token offering for the funding
        IERC20 tokenCA;
    }

    /**
     *  notice: Overflow method is used for investors willing to invest in a proposal
     *  Overflow method curb the rush of first come, first serve and create equality
     *  among all investors, any investor that invest within the investing period will 
     *  have equal rate of equity offering (depending on investor amount funded).
     * 
     *  In this case, amount funded may be greater than the funding requested, but the 
     *  amount that will be given to the proposal creator will always be equal to the
     *  fund requested provided the fund raised is equal or greater than the funding 
     *  request.
     */
    
    struct Invest {
        string url;
        address proposalCreator;
        uint40 investPeriod;
        uint48 investId;
        bool funded;
        uint256 fundingRequest; // Request in dollar
        uint256 equityOffering; // token offering for the funding
        uint256 amountFunded;
        IERC20 _tokenCA;
    }

    struct FundedProject {
        string url;
        uint256 fundingRequest;
        uint256 amountFunded;
        uint256 equityOffering;
        uint96 investorsTag;
        address proposalCreator;
        IERC20 _tokenCA;
        bool claimed;
    }

    enum Status {
        approve,
        pending,
        reject
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
        address sender = msg.sender; // variable caching
        uint256 _amount = msg.value; // variable caching
        if(_amount < acceptanceFee) revert lowerThanFee("VENDAO: fee is less than the required fee");
        DAO_FTM_BALANCE += _amount;
        _grantRole(INVESTOR, sender);
        _newTokenId = _daoPassTicket(sender);
        investorsId[msg.sender] = _newTokenId;
        voteLimit[sender] = 0;
    }

    /**
     * @notice  . When an investor decides to leave the DAO, access ticket is burnt
     * and only 50% of the amount used to join the DAO is refunded.
     * @dev     . Function responsible for leaving the DAO
     */
    function leaveDAO() external payable onlyRole(INVESTOR) {
        address sender = msg.sender;
        _revokeRole(INVESTOR, sender);
        _burn(investorsId[sender]);
        
        (bool success, ) = payable(sender).call{value: (acceptanceFee / 2)}("");

        require(success, "Transaction Unsuccessful");
    }

    // ================ VOTING ARENA ===================

    function setContestant(Contestant memory _contestant, uint40 _voteTime) external {
        if(msg.sender != owner()) revert notAdmin("VENDAO: Only admin can alter change");
        require(contestant.length < 10, "Contestant filled");
        contestant.push(_contestant);
        voteTime = _voteTime;
    }

    /**
     * @notice  . This function can only be called by admin
     * @dev     . Function responsible for reseting contestant inputs.
     */
    function resetContestant() external {
        if(msg.sender != owner()) revert notAdmin ("VENDAO: Only admin can alter change");
        for(uint i = 0; i < 10; i ++) {
            contestant.pop();
        }
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

    function top5Nominees() external view returns(Contestant[] memory) {
        Contestant[] memory _contestant = contestant;
        Contestant[] memory nominees = new Contestant[](5);

        Contestant memory max;
        uint8 index;
        for(uint8 i = 0; i < 5; i++){
            max = nominees[0];
            index = 0;

            for(uint8 j = 0; j < _contestant.length; j++){
                if(max.voteCount < _contestant[j].voteCount){
                    max = _contestant[j];
                    index = j;
                }
            }
            nominees[i] = max;
            delete _contestant[index];
        }
        return nominees;
    }

    // ================ Project Proposal Section ====================

    /**
     * @notice  . Any body can call this function to propose a project
     * @dev     . Function responsible for taking project proposal before, it's being moved to the dao for invedtors
     * @param   _urlToStore  . url to the storage location of the project proposal overview
     */
    /**
     * @notice  . Any body can call this function to propose a project
     * @dev     . Function responsible for taking project proposal before, it's being moved to the dao for invedtors
     * @param   _urlToStore  . url to the storage location of the project proposal overview
     * @param   _fundingRequest  . amount requesting for funding in dollars
     * @param   _equityOffering  . amount of equity offering for that funding
     * @param   _contractAddress  . contract address of the token (equity)
     */
    function proposeProject(string memory _urlToStore, uint256 _fundingRequest, uint256 _equityOffering, IERC20 _contractAddress) external nonReentrant {
        uint48 index = uint48(projectProposals.length);
        address sender = msg.sender;
        require(_contractAddress.transferFrom(sender, address(this), _equityOffering), "VENDAO: Transaction unsuccessful");
        require(_contractAddress.balanceOf(address(this)) >= _equityOffering, "VENDAO: zero value was sent");
        projectProposals.push(Project({
            urlToStorage: _urlToStore,
            proposalValidity: uint40(block.timestamp + 2 weeks),
            proposalCreator: sender,
            proposalId: index,
            approvalCount: 0,
            status: Status.pending,
            fundingRequest: _fundingRequest,
            equityOffering: _equityOffering,
            tokenCA: _contractAddress
        }));
    }

    /**
     * @notice  . This function can only be called by the nominated admins 
     * @dev     . The function examine project is used to approve/reject a project
     * @param   _proposalId  . proposal id of a project
     */
    function examineProject(uint48 _proposalId) external onlyRole(NOMINATED_ADMINS) nonReentrant {
        Project memory _proposal = projectProposals[_proposalId];
        require(!nomineesApproved[msg.sender][_proposalId], "NOMINEE: Approved already");
        if(_proposal.status == Status.approve) revert approved("VENDAO: Project proposal approved");

        if((block.timestamp > _proposal.proposalValidity) && (_proposal.status == Status.pending)) {
            projectProposals[_proposalId].status = Status.reject;
            require((_proposal.tokenCA).transfer(_proposal.proposalCreator, _proposal.equityOffering), "Transfer unsuccessful");

        }else {
            uint8 _count = projectProposals[_proposalId].approvalCount;
            if(_count > 3) {
                projectProposals[_proposalId].status = Status.approve;
                uint48 index = uint48(proposalsToInvest.length);
                proposalsToInvest.push(Invest({
                    url: _proposal.urlToStorage,
                    proposalCreator: _proposal.proposalCreator,
                    investPeriod: uint40(block.timestamp + 2 weeks),
                    investId: index,
                    funded: false,
                    fundingRequest: _proposal.fundingRequest,
                    equityOffering: _proposal.equityOffering,
                    amountFunded: _daoFundingCalc(_proposal.fundingRequest),
                    _tokenCA: _proposal.tokenCA
                }));
            }
        } 
    }

    /**
     * @notice  . This function can only be called by investors
     * @dev     . Function responsible for investors to invest in a project of their choice
     * @param   _proposalId  . proposal id of project requesting for funding
     */
    function invest(uint48 _proposalId) external payable onlyRole(NOMINATED_ADMINS) nonReentrant {
        uint256 _amount = msg.value; // variable caching
        Invest memory _invest = proposalsToInvest[_proposalId];
        if(block.timestamp >= _invest.investPeriod) {
            if(_invest.amountFunded > _invest.fundingRequest) {
                proposalsToInvest[_proposalId].funded = true;
                projectFunded.push(FundedProject({
                    url: _invest.url,
                    fundingRequest: _invest.fundingRequest,
                    amountFunded: _invest.amountFunded,
                    equityOffering: _invest.equityOffering,
                    investorsTag: uint96(_invest.investId),
                    proposalCreator: _invest.proposalCreator,
                    _tokenCA: _invest._tokenCA,
                    claimed: false
                }));
            }else {
                proposalsToInvest[_proposalId].equityOffering = 0;
                require((_invest._tokenCA).transfer(_invest.proposalCreator, _invest.equityOffering), "Transfer unsuccessful");
            }
        }else {
            investorFund[msg.sender][_proposalId] += _amount;
            proposalsToInvest[_proposalId].amountFunded += _amount;
        }     
    }

    function projectNotSuccessful(uint48 _proposalId) external view returns(bool) {
        Invest memory _invest = proposalsToInvest[_proposalId];
        if(block.timestamp >= _invest.investPeriod && _invest.amountFunded < _invest.fundingRequest) {
            return true;
        }else {
            return false;
        }
    }

    function claim(uint48 _proposalId) external nonReentrant {
        address sender = msg.sender; // variable caching;
        FundedProject memory _fundedProject = projectFunded[_proposalId];
        if(sender == _fundedProject.proposalCreator) {
            require(!_fundedProject.claimed, "already claimed");
            projectFunded[_proposalId].claimed = true;

            (, uint256 amountUsed,) = _investorClaimCalc(
                _fundedProject.fundingRequest,
                _fundedProject.amountFunded,
                _fundedProject.equityOffering,
                _daoFundingCalc(_fundedProject.fundingRequest)
            );
            DAO_FTM_BALANCE -= amountUsed;

            (bool success, ) = payable(sender).call{value: _fundedProject.fundingRequest}("");

            require(success, "Transaction unsuccessful");
        }else {
            uint256 amountInvested = investorFund[sender][uint48(_fundedProject.investorsTag)];
            (uint256 share,, uint256 amountLeft) = _investorClaimCalc(
                _fundedProject.fundingRequest,
                _fundedProject.amountFunded,
                _fundedProject.equityOffering,
                amountInvested
            );
            investorFund[sender][uint48(_fundedProject.investorsTag)] = 0;
            require((_fundedProject._tokenCA).transfer(sender, share), "Transfer unsuccessful");
            (bool success, ) = payable(sender).call{value: amountLeft}("");

            require(success, "Transaction unsuccessful");
        }
    }

    /**
    * @dev  . Function that holds access ticket URI
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

    function _daoFundingCalc(uint256 _fundingRequest) internal view returns(uint256) {
        uint256 investingAmount = (10 * _fundingRequest) / 100;
        if(DAO_FTM_BALANCE >= investingAmount){
            return investingAmount;
        }else {
            return 0;
        }
    }

    function _investorClaimCalc(
        uint256 _fundingRequest,
        uint256 _fundingRaised,
        uint256 _equityOffering,
        uint256 _amountInvested
    )
    internal pure returns(uint256 _share, uint256 _amountUsed, uint256 _amountLeft) {
        _share = (_equityOffering * _amountInvested) / _fundingRaised;
        _amountUsed = (_fundingRequest * _amountInvested) / _fundingRaised;
        _amountLeft = _amountInvested - _amountUsed;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControlDefaultAdminRules) returns (bool){
        return super.supportsInterface(interfaceId);
    }

    receive() external payable {}
    fallback() external payable {}
}