// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./IVenAccessTicket.sol";
import "./IVenAccessControl.sol";
import "./ISpookySwap.sol";

contract Vendao is ReentrancyGuard{
    bytes32 public constant NOMINATED_ADMINS = keccak256("NOMINATED_ADMINS");
    bytes32 public constant INVESTOR = keccak256("INVESTOR");
    bytes32 public constant ADMIN = keccak256("ADMIN");

    /**===================================
     *            Custom Error
    =====================================*/
    error notAdmin(string);
    error lowerThanFee(string);
    error approved(string);
    error _paused(string);

    /**===================================
     *            EVENTS
    =====================================*/

    /*====================================
    **           STATE VARIBLES
    =====================================*/
    address owner;

    IVenAccessTicket public VenAccessTicket;
    IVenAccessControl public VenAccessControl;
    ISpookySwap public spookySwap;
    uint208 acceptanceFee;
    uint40 public proposalTime;
    bool paused;
    mapping(address => mapping(uint48 => bool)) nomineesApproved;
    uint256 DAO_FTM_BALANCE;
    mapping(address => mapping(uint256 => uint256)) investorFund;
    mapping(address => uint256) investorsId;
    Project[] public projectProposals; // List of project proposals
    Invest[] public proposalsToInvest; // List of proposals to invest in
    FundedProject[] public projectFunded; // List of project funded


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


    constructor() {
        owner = msg.sender;
    }

    function init(IVenAccessTicket _accessTicket, IVenAccessControl _accessControl, ISpookySwap _spookyswap) external {
        require(msg.sender == owner, "Not an owner");
        VenAccessTicket = _accessTicket;
        VenAccessControl = _accessControl;
        spookySwap = _spookyswap;

        delete owner;
    }

    function changeDex(ISpookySwap _spookyswap) external {
        if(!VenAccessControl.hasRole(ADMIN, msg.sender)) revert notAdmin("VENDAO: Only admin can alter change");
        spookySwap = _spookyswap;
    }

    /**
     * @dev     . function responsible to set acceptance fee
     * @param   _acceptance  . New acceptance fee to be set
     */
    function setAcceptanceFee(uint208 _acceptance) external {
        if(!VenAccessControl.hasRole(ADMIN, msg.sender)) revert notAdmin("VENDAO: Only admin can alter change");
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
        VenAccessControl.grantRole(INVESTOR, sender);
        _newTokenId = VenAccessTicket.daoPassTicket(sender);
        investorsId[sender] = _newTokenId;
    }

    /**
     * @notice  . When an investor decides to leave the DAO, access ticket is burnt
     * and only 50% of the amount used to join the DAO is refunded.
     * @dev     . Function responsible for leaving the DAO
     */
    function leaveDAO() external payable {
        address sender = msg.sender;
        require(VenAccessControl.hasRole(INVESTOR, sender), "VENDAO: Not an investor");
        VenAccessControl.revokeRole(INVESTOR, sender);
        VenAccessTicket.burnPassTicket(investorsId[sender]);
        
        (bool success, ) = payable(sender).call{value: (acceptanceFee / 2)}("");

        require(success, "Transaction Unsuccessful");
    }

    // ================ Project Proposal Section ====================

    /**
     * @notice  . Any body can call this function to propose a project
     * @dev     . Function responsible for taking project proposal before, it's being moved to the dao for invedtors
     * @param   _urlToStore  . url to the storage location of the project proposal overview
     */
    /**
     * @notice  . Any body can call this function to propose a project. Project can only be proposed once in a week
     * @dev     . Function responsible for taking project proposal before, it's being moved to the dao for invedtors
     * @param   _urlToStore  . url to the storage location of the project proposal overview
     * @param   _fundingRequest  . amount requesting for funding in dollars
     * @param   _equityOffering  . amount of equity offering for that funding
     * @param   _contractAddress  . contract address of the token (equity)
     */
    function proposeProject(string memory _urlToStore, uint256 _fundingRequest, uint256 _equityOffering, IERC20 _contractAddress) external nonReentrant {
        uint48 index = uint48(projectProposals.length);
        address sender = msg.sender; // variable caching
        uint40 timestamp = uint40(block.timestamp); // variable caching
        require(timestamp > proposalTime, "Proposal not open");
        if(paused) revert _paused("Project proposal paused");
        require(_contractAddress.transferFrom(sender, address(this), _equityOffering), "VENDAO: Transaction unsuccessful");
        require(_contractAddress.balanceOf(address(this)) >= _equityOffering, "VENDAO: zero value was sent");
        projectProposals.push(Project({
            urlToStorage: _urlToStore,
            proposalValidity: uint40(timestamp + 2 weeks),
            proposalCreator: sender,
            proposalId: index,
            approvalCount: 0,
            status: Status.pending,
            fundingRequest: _fundingRequest,
            equityOffering: _equityOffering,
            tokenCA: _contractAddress
        }));

        proposalTime = timestamp + 1 weeks;
    }

    /**
     * @notice  . This can only be called by the admin
     * @dev     . Function pause proposal is used to prevent excessive project proposals
     */
    function pauseProposal() external {
        require(VenAccessControl.hasRole(ADMIN, msg.sender), "VENDAO: Not an admin");
        paused = true;
    }

    /**
     * @notice  . This function can only be called by the nominated admins 
     * @dev     . The function examine project is used to approve/reject a project
     * @param   _proposalId  . proposal id of a project
     */
    function examineProject(uint48 _proposalId) external nonReentrant {
        address sender = msg.sender;
        if(!VenAccessControl.hasRole(NOMINATED_ADMINS, sender)) revert notAdmin("Only nominated admins can alter change");
        Project memory _proposal = projectProposals[_proposalId];
        require(!nomineesApproved[sender][_proposalId], "NOMINEE: Approved already");
        if(_proposal.status == Status.approve) revert approved("VENDAO: Project proposal approved");

        if((block.timestamp > _proposal.proposalValidity) && (_proposal.status == Status.pending)) {
            projectProposals[_proposalId].status = Status.reject;
            require((_proposal.tokenCA).transfer(_proposal.proposalCreator, _proposal.equityOffering), "Transfer unsuccessful");

        }else {
            uint8 _count = projectProposals[_proposalId].approvalCount;
            investorFund[sender][_proposalId] += incentiveCalc(_proposal.fundingRequest);
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
    function invest(uint48 _proposalId) external payable nonReentrant {
        if(!VenAccessControl.hasRole(INVESTOR, msg.sender)) revert notAdmin("Only Investors");
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
     * @notice  . This function can only be called by an admin. It is used to take profit
     *  by converting equity offered to stable token, to grow VENDAO treasury.
     * @dev     . The function is used to convert token to stable token.
     * @param   _token  . address of equity offered (token to change)
     * @param   _stable  . address of stable token
     * @param   _amount  . amount intending to swap to stable token
     * @param   _dataFeed  . oracle price feed, if any, else null address should be used
     * @param   _amountOutMin  . this should be set to zero if _datafeed is filled. it is used in case
     *  There's no _datafeed
     */
    function takeProfitInStable(
        IERC20 _token,
        IERC20 _stable,
        uint256 _amount,
        AggregatorV3Interface _dataFeed,
        uint256 _amountOutMin
        ) external nonReentrant {
        if(!VenAccessControl.hasRole(ADMIN, msg.sender)) revert notAdmin("VENDAO: Only admin can alter change");
        require(_token.approve(address(spookySwap), _amount), "approve failed");
        address[] memory path = new address[](3);

        path[0] = address(_token);
        path[1] = spookySwap.WETH();
        path[2] = address(_stable);
        // get data feed
        (,int _price,,,) = _dataFeed.latestRoundData();
        if(_price > 0){
            spookySwap.swapExactTokensForTokens(_amount, uint256(_price), path, address(this), (block.timestamp + 20 seconds));
        }else {
            spookySwap.swapExactTokensForTokens(_amount, _amountOutMin, path, address(this), (block.timestamp + 20 seconds));
        }
    }

    
    /**
     * @notice  . This function can only be called by an admin. It is used to take profit
     *  by converting equity offered to FTM, to grow VENDAO treasury.
     * @dev     . The function is used to convert token to FTM.
     * @param   _token  . address of equity offered (token to change)
     * @param   _amount  . amount intending to swap for FTM
     * @param   _dataFeed  . oracle price feed, if any, else null address should be used
     * @param   _amountOutMin  . this should be set to zero if _datafeed is filled. it is used in case
     *  There's no _datafeed
     */
    function takeProfitInFTM(
        IERC20 _token,
        uint256 _amount,
        AggregatorV3Interface _dataFeed,
        uint256 _amountOutMin
    ) external nonReentrant {
        if(!VenAccessControl.hasRole(ADMIN, msg.sender)) revert notAdmin("VENDAO: Only admin can alter change");
        require(_token.approve(address(spookySwap), _amount), "approve failed");
        address[] memory path = new address[](2);

        path[0] = address(_token);
        path[1] = spookySwap.WETH();
        // get data feed
        (,int _price,,,) = _dataFeed.latestRoundData();
        if(_price > 0){
            spookySwap.swapExactTokensForETH(_amount, uint256(_price), path, address(this), (block.timestamp + 20 seconds));
        }else {
            spookySwap.swapExactTokensForETH(_amount, _amountOutMin, path, address(this), (block.timestamp + 20 seconds));
        }
    }

    // ======================= VIEW FUNCTIONS =======================

    function ftmBalance() external view returns(uint256) {
        return DAO_FTM_BALANCE;
    }

    function tokenBalance(IERC20 _tokenAddress) external view returns(uint256) {
        return _tokenAddress.balanceOf(address(this));
    }


    // ===================== INTERNAL FUNCTIONS ====================

    function _daoFundingCalc(uint256 _fundingRequest) internal view returns(uint256) {
        uint256 investingAmount = (10 * _fundingRequest) / 100;
        if(DAO_FTM_BALANCE >= investingAmount){
            return investingAmount;
        }else {
            return 0;
        }
    }

    function incentiveCalc(uint256 _fundingRequest) internal pure returns(uint256 incentive) {
        incentive = (1 * _fundingRequest) / 10000; // 0.01% as the incentive fee
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

    receive() external payable {}
    fallback() external payable {}
}