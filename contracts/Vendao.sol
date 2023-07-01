// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./IVenAccessTicket.sol";
import "./IVenAccessControl.sol";
import "./ISpookySwap.sol";

contract Vendao is ReentrancyGuard{
    bytes32 public constant NOMINATED_ADMINS = keccak256("NOMINATED_ADMINS");
    bytes32 public constant INVESTOR = keccak256("INVESTOR");

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
    event _changeAcceptance(uint128, uint128);
    event _joinDao(address, uint256);

    /*====================================
    **           STATE VARIBLES
    =====================================*/
    address owner;

    IVenAccessTicket VenAccessTicket;
    IVenAccessControl public VenAccessControl;
    ISpookySwap public spookySwap;
    AggregatorV3Interface public FTM_PRICE_FEED;
    uint128 acceptanceFee;
    uint40 public proposalTime;
    bool paused;
    mapping(address => mapping(uint256 => bool)) nomineesApproved;
    uint256 public DAO_FTM_BALANCE;
    mapping(address => InvestorDetails) public investorDetails;
    Project[] public projectProposals; // List of project proposals
    Invest[] public proposalsToInvest; // List of proposals to invest in
    FundedProject[] public projectFunded; // List of project funded

    struct InvestorDetails {
        mapping(uint256 => uint256) investorFund;
        uint128 investmentCount;
        uint128 shareCount;
        uint256 amountSpent;
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
        uint256 fundingRequest; // Request in ftm
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

    function init(IVenAccessTicket _accessTicket, IVenAccessControl _accessControl, ISpookySwap _spookyswap, AggregatorV3Interface _ftm_price_feed) external {
        require(msg.sender == owner, "Not an owner");
        VenAccessTicket = _accessTicket;
        VenAccessControl = _accessControl;
        spookySwap = _spookyswap;
        FTM_PRICE_FEED = _ftm_price_feed;

        delete owner;
    }

    function setVar(uint128 _acceptance) external {
        uint128 oldFee = acceptanceFee;
        if(msg.sender != VenAccessControl.owner()) revert notAdmin("VENDAO: Only admin can alter change");
        acceptanceFee = _acceptance;
        emit _changeAcceptance(oldFee, acceptanceFee);
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

        emit _joinDao(sender, _newTokenId);
    }

    // ================ Project Proposal Section ====================

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
        (,int _price,,,) = FTM_PRICE_FEED.latestRoundData();
        uint256 _funding = _fundingRequest * 10**8 / uint256(_price);
        projectProposals.push(Project({
            urlToStorage: _urlToStore,
            proposalValidity: uint40(timestamp + 4 weeks),
            proposalCreator: sender,
            proposalId: index,
            approvalCount: 0,
            status: Status.pending,
            fundingRequest: _funding,
            equityOffering: _equityOffering,
            tokenCA: _contractAddress
        }));

        proposalTime = timestamp + 1 weeks;

        
    }

    function reProposeProject(uint48 _proposalId, string memory _urlToStore, uint256 _fundingRequest, uint256 _equityOffering) external nonReentrant {
        address sender = msg.sender; // variable caching
        Project storage _proposal = projectProposals[_proposalId];
        IERC20 _contractAddress = _proposal.tokenCA;
        require(_proposal.status == Status.pending && sender == _proposal.proposalCreator, "Modification imposible");
        (,int _price,,,) = FTM_PRICE_FEED.latestRoundData();
        uint256 _funding = _fundingRequest * 10**8 / uint256(_price);

        _proposal.urlToStorage = _urlToStore;
        _proposal.proposalValidity = uint40(block.timestamp + 4 weeks);
        _proposal.approvalCount = 0;
        _proposal.fundingRequest = _funding;

        if(_equityOffering > _proposal.equityOffering) {
            uint256 toBalance = (_equityOffering - _proposal.equityOffering);
            require(_contractAddress.transferFrom(sender, address(this), toBalance), "VENDAO: Transaction unsuccessful");
            require(_contractAddress.balanceOf(address(this)) >= _equityOffering, "VENDAO: zero value was sent");
        } else {
            uint256 _balance = (_proposal.equityOffering - _equityOffering);
            _proposal.equityOffering = _equityOffering;
            require(_contractAddress.transfer(sender, _balance), "VENDAO: Transaction unsuccessful");
        }
        _proposal.equityOffering = _equityOffering;
    }

    /**
     * @notice  . This can only be called by the admin
     * @dev     . Function pause proposal is used to prevent excessive project proposals
    */
    function pauseProposal() external {
        if(msg.sender != VenAccessControl.owner()) revert notAdmin("VENDAO: Only admin can alter change");
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
            investorDetails[sender].investorFund[_proposalId] = incentiveCalc(_proposal.fundingRequest);
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
        address sender = msg.sender; // variable cat
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
            InvestorDetails storage _investDetails = investorDetails[sender];
            if(_investDetails.investorFund[_proposalId] == 0) {
                _investDetails.investmentCount += 1;
            }
            _investDetails.investorFund[_proposalId] += _amount;
            (,int _price,,,) = FTM_PRICE_FEED.latestRoundData();
            uint256 _amountSpent = (_amount * uint256(_price)) / 10**8;
            _investDetails.amountSpent += _amountSpent;
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
            uint256 amountInvested = investorDetails[sender].investorFund[(uint48(_fundedProject.investorsTag))];
            (uint256 share,, uint256 amountLeft) = _investorClaimCalc(
                _fundedProject.fundingRequest,
                _fundedProject.amountFunded,
                _fundedProject.equityOffering,
                amountInvested
            );
            
            investorDetails[sender].investorFund[(uint48(_fundedProject.investorsTag))] = 0;
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
        if(msg.sender != VenAccessControl.owner()) revert notAdmin("VENDAO: Only admin can alter change");
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
        if(msg.sender != VenAccessControl.owner()) revert notAdmin("VENDAO: Only admin can alter change");
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

    function tokenBalance(IERC20 _tokenAddress) external view returns(uint256) {
        return _tokenAddress.balanceOf(address(this));
    }

    function getLength() external view returns(uint256 getProductLength, uint256 getInvestLength, uint256 getFundedLength) {
        getProductLength = projectProposals.length;
        getInvestLength = proposalsToInvest.length;
        getFundedLength = projectFunded.length;
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
}