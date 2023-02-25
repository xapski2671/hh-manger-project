// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

// errors
error Campaign__NotInState();
error Campaign__NotCreator(address _address);
error Campaign__DonatorIsCreator(address _address);
error Campaign__PayoutFailed();
error Campaign__NoDonationsHere(address _donatorAddress);
error Campaign__RefundFailed();
error Campaign__UpkeepNotNeeded();
error Campaign__NotWithrawable(address _campaignAddress);
error Campaign__AlreadyExpired(address _campaignAddress);
error Campaign__NotRefundable(address _campaignAddress);
error Campaign__CampaignBankrupt(address _campaignAddress);


contract Campaign is KeeperCompatibleInterface {
  using SafeMath for uint256;

  // enums
  enum State {
    Successful,
    Fundraising,
    Expired
  }


  // state variables
  address payable public creator;
  string public title;
  string public description;
  string public category;
  string[] public tags;
  uint256 public goalAmount;
  uint256 public duration;
  uint256 public currentBalance;
  uint256 private s_lastTimeStamp;
  State public state = State.Fundraising; // default state
  mapping (address => uint256) public donations;
  bool public nowPayable;
  bool public nowRefundable;


  struct CampaignObject {
    address creator;
    string title;
    string description;
    string category;
    string[] tags;
    uint256 goalAmount;
    uint256 duration;
    uint256 currentBalance;
    State currentState;
  }


  // events
  event FundingRecieved (
    address indexed contributor,
    uint256 amount,
    uint256 currentBalance
  );
  event CreatorPaid(address creator, address campaignAddress);
  event CampaignSuccessful(address campaignAddress);
  event CampaignExpired(address campaignAddress);


  // modifiers
  modifier isCreator() {
    if(msg.sender != creator){revert Campaign__NotCreator(msg.sender);}
    _;
  }

  constructor (
    address _creator,
    string memory _title,
    string memory _description,
    string memory _category,
    string[] memory _tags,
    uint256 _goalAmount,
    uint256 _duration
  ) {
    creator = payable(_creator);
    title = _title;
    description = _description;
    category = _category;
    tags = _tags;
    goalAmount = _goalAmount;
    duration = _duration;
    s_lastTimeStamp = block.timestamp;
    currentBalance = 0;
    nowPayable = false;
    nowRefundable = true;
  }

  function donate() external payable {
    if(state == State.Fundraising || state == State.Successful){revert Campaign__AlreadyExpired(address(this));}
    if (msg.sender == creator){revert Campaign__DonatorIsCreator(msg.sender);}
    donations[msg.sender] = donations[msg.sender].add(msg.value);
    currentBalance = currentBalance.add(msg.value);
    emit FundingRecieved(msg.sender, msg.value, currentBalance);
  }

  /**
    @dev this is the function chainlink keepers calls
    chekupkeep returns true to trigger the action after the interval has passed
   */
  function checkUpkeep(bytes memory /**checkData */) public view override
  returns (bool upkeepNeeded, bytes memory /**performData */) 
  {
    bool isOpen = state == State.Fundraising;
    bool timePassed = ((block.timestamp - s_lastTimeStamp) > duration);
    bool hasBalance = address(this).balance > 0;
    upkeepNeeded = (timePassed && isOpen && hasBalance) ;
    return (upkeepNeeded, "0x0");
  }

  function performUpkeep(bytes calldata /**performData */) external override {
    (bool upkeepNeeded, ) = checkUpkeep("");
    if(!upkeepNeeded){revert Campaign__UpkeepNotNeeded();}

    // allow creator withdraw funds
    nowPayable = true;

    if((block.timestamp - s_lastTimeStamp) > duration){
      state = State.Expired;
      nowRefundable = false; 
      emit CampaignExpired(address(this));
      if(currentBalance >= goalAmount){
        emit CampaignSuccessful(address(this));
      }
    }
  }

  function payout() public isCreator {
    if(!nowPayable){revert Campaign__NotWithrawable(address(this));}
    uint256 totalRaised = currentBalance;
    currentBalance = 0;
    (bool success, ) = creator.call{value: totalRaised}("");
    if(success){
      nowRefundable = false;
      emit CreatorPaid(creator, address(this));
    }
    else{revert Campaign__PayoutFailed();}
  }

  function refund(address _donator) public {
    if(!nowRefundable){revert Campaign__NotRefundable(address(this));}
    if(donations[_donator] <= 0){revert Campaign__NoDonationsHere(msg.sender);}
    uint256 amountToRefund = donations[_donator];
    donations[_donator] = 0;
    if(currentBalance < amountToRefund){revert Campaign__CampaignBankrupt(address(this));}
    currentBalance = currentBalance.sub(amountToRefund);
    (bool success, ) = payable(_donator).call{value: amountToRefund}("");
    if(!success){revert Campaign__RefundFailed();} // TODO: test if it returns the money to mapping
  }

  function endCampaign() public isCreator {
    if(state == State.Expired){revert Campaign__AlreadyExpired(address(this));}
    state = State.Expired;
    nowRefundable = false;
    if(currentBalance > 0){nowPayable = true;}
    emit CampaignExpired(address(this));
  }

  // update functions
  function updateTitle(string memory _newTitle) public isCreator {
    title = _newTitle;
  }

  function updateDescription(string memory _newDescription) public isCreator {
    description = _newDescription;
  }
  
  // getter functions
  function getBalance() public view returns(uint256) {
    return currentBalance;
  }

  function getCampaignState() public view returns(State) {
    return state;
  }

  function getDonations(address _donator) public view returns(uint256) {
    return donations[_donator];
  }

  function getCampaignDetails() public view returns(CampaignObject memory) {
    return CampaignObject(
      creator,
      title,
      description,
      category,
      tags,
      goalAmount,
      duration,
      currentBalance,
      state
    );
  }
}