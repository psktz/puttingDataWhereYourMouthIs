pragma solidity ^0.5.7;


// #####################
// LIBRARIES
// #####################

import "./ABDKMathQuad.sol";

contract PrototypeOne {

    using ABDKMathQuad for *;

    // #####################
    // CONTRACT VARIABLES
    // #####################

    struct dataSet{
        mapping(address => uint8) buyers;
        mapping(address => int) cleanClaims;
        mapping(address => int) advClaims;
        string[] adversarialMethods;

        address payable[] cleanClaimantsArray;
        address payable[] advClaimantsArray;
        address payable[]  buyersArray;
        address payable  thirdPartyAddress;
        address payable seller;

        bytes16 totalCleanPool;
        bytes16 totalAdvPool;

        uint  start;
        uint  end;
        uint  price;
        uint  testerShare;
        uint  testPool;
        uint startTime;
        uint  ownerDeposit;
        uint  cleanCount;
        uint  advCount;
        uint  buyerIndex;
        uint  possibleClients;
        bytes16 priceBytes16;
        bytes16 decay;
        uint neededDeposit;
        int8 decision;

        bytes16 possibleClients16;
        bytes16 formulaDenominator;
        bool  collateralWasPaid;
        uint coveredDeposits;
        bytes16 testerShare16;
        bool  thirdPartyInvoked;
        bool  forcedThirdInvocation;
    }

    dataSet[] dataSetArray;

    // #####################
    // CONSTANTS
    // #####################


    uint hundred;
    bytes16 hundred16;
    int negOne;
    bytes16 negOne16;

    // #####################
    // MODIFIERS
    // #####################

    modifier onlySeller(uint _datasetIndex) {
        require(msg.sender == dataSetArray[_datasetIndex].seller);
         _;
    }

    modifier onlyBuyer(uint _datasetIndex){
        require(dataSetArray[_datasetIndex].buyers[msg.sender]==1);
        _;
    }

    modifier onlyThirdParty(uint _datasetIndex){
        require(msg.sender == dataSetArray[_datasetIndex].thirdPartyAddress);
        _;
    }


    // #####################
    // EVENTS
    // #####################


    event DatasetCreation(
        uint _price,
        uint _possibleClients,
        uint _decayPct,
        uint _durationInDays,
        uint _testerShare,
        address _sellerAddress,
        uint _datasetIndex);
    event SellerDeposit(address depAddress, uint depositedValue, uint valueForTestPool);
    event BuyerDeposit(address depAddress, uint depositedValue, uint valueForTestPool, uint IndexOfBuyer);
    event TransferToAdversarial(address transferAddress);
    event CleanClaim(address claimantAddress, uint claimNumber);
    event AdversarialClaim(address claimantAddress, string advMethod, uint claimNumber);
    event ClaimantWithdrawal(uint dsIndex,address claimAddress, uint amountWithdrawn);
    event SellerWithdrawal(uint dsIndex,address sellerAddress, uint amountWithdrawn);
    event ThirdPartyInvocation(uint dsIndex,address invokerAddress);
    event BuyerRefund(uint dsIndex,address buyerAddress);
    event ThirdPartyDecision(uint dsIndex,address thirdPartyAddress, int decision);
    event ThirdPartyPayment(uint dsIndex,address thirdPartyAddress, uint amountWithdrawn);
    event ForcedThirdPartyDecision(uint dsIndex,address thirdPartyAddress, uint cost, int decision);


    constructor() public{
        hundred = 100;
        hundred16 = hundred.fromUInt();
        negOne = - 1;
        negOne16 = negOne.fromInt();
    }


    // #####################
    // FUNCTIONS
    // #####################

    /*
    Function that the seller must call to post the dataset.
    Parameters:
        _price : the price of the dataset
        _possibleClients : the expected amount of people that will buy the dataset (affects seller's deposit decay)
        _decaypct : variable that affects the deposit decay (in percentages)
        _durationInDays : period of time in days when the people can buy the dataset and submit claims
        _testerShare : value in percentage points that gets offered to testers to incentivise them to test the dataset
        _thirdPartyAddress: address of the thirdParty that gets to have the final decision in case voting does not provide
                        a conclusion
    */
    function postDataset(uint _price,
        uint _possibleClients,
        uint _decayPct,
        uint _durationInDays,
        uint _testerShare,
        address payable _thirdPartyAddress) public{

        dataSet memory dataset;
        dataset.price = _price;
        dataset.possibleClients = _possibleClients;
        dataset.testerShare = _testerShare;
        dataset.possibleClients16 = _possibleClients.fromUInt();
        dataset.priceBytes16 = _price.fromUInt();
        dataset.decay = _decayPct.fromUInt();
        dataset.decay = dataset.decay.div(hundred16);
        dataset.testerShare16 = (_testerShare.fromUInt()).div(hundred16);
        dataset.formulaDenominator = dataset.decay.mul(dataset.possibleClients16.mul(negOne16));
        dataset.start = now;
        dataset.end = now + (_durationInDays * 1 days);
        dataset.collateralWasPaid = false;
        dataset.coveredDeposits = 0;
        dataset.thirdPartyInvoked = false;
        dataset.forcedThirdInvocation = false;
        dataset.thirdPartyAddress = _thirdPartyAddress;
        dataset.seller = msg.sender;
        dataset.startTime = now;

        dataSetArray.push(dataset);


        emit DatasetCreation(_price,
                            _possibleClients,
                            _decayPct,
                            _durationInDays,
                            _testerShare,
                            msg.sender,
                            dataSetArray.length-1);
    }


    /*
    Helper function that calculates the amount of wei/eth that the seller must
    deposit for the buyer with index "index"

    Parameters:
        - datasetIndex: the primary key used to identify each dataset in the contract


    */
    function calcDepositByIndex(uint _datasetIndex, uint _index) internal view returns (bytes16) {
        bytes16 index16 = _index.fromUInt();
        bytes16 fraction = index16.div(dataSetArray[_datasetIndex].formulaDenominator);
        bytes16 multiplier = fraction.exp();
        return dataSetArray[_datasetIndex].priceBytes16.mul(multiplier);
    }


    /*
    Internal function that calculates the amount of wei/eth that a claimant has to pay/has paid
    for a claim depending on the timing of the claim

    Parameters:
        - datasetIndex: the primary key used to identify each dataset in the contract
    */
    function calcBetSizeByIndex(uint _datasetIndex, uint _index) internal view returns(bytes16){
        return calcDepositByIndex(_datasetIndex,_index).mul(dataSetArray[_datasetIndex].testerShare16);
    }

    /*
    Getter function that returns the total amount the seller must deposit for him to
    be "in good standing"

    Parameters:
        - datasetIndex: the primary key used to identify each dataset in the contract
    */
    function calculateSellerDeposit(uint _datasetIndex) public  view returns (uint) {
        return dataSetArray[_datasetIndex].neededDeposit;
    }


    /*
    Function that buyers must use in order to buy a dataset
    datasetIndex: index of the dataset that is given by the seller (he receives it in the receipt of "postDataset"

    Parameters:
        - datasetIndex: the primary key used to identify each dataset in the contract
    */
    function buyDataset(uint _datasetIndex)  public payable{
        require(now < dataSetArray[_datasetIndex].end - 1 days);
        require(dataSetArray[_datasetIndex].buyers[msg.sender] == 0);
        require(msg.sender != dataSetArray[_datasetIndex].seller);

        dataSetArray[_datasetIndex].buyersArray.push(msg.sender);
        dataSetArray[_datasetIndex].buyers[msg.sender] = 1;
        dataSetArray[_datasetIndex].neededDeposit += calcDepositByIndex(_datasetIndex,
                                                                        dataSetArray[_datasetIndex].buyerIndex).toUInt();
        dataSetArray[_datasetIndex].buyerIndex++;
        dataSetArray[_datasetIndex].collateralWasPaid = false;


        emit BuyerDeposit(msg.sender, msg.value, msg.value, dataSetArray[_datasetIndex].buyerIndex);
    }

    /*
    Function that the seller must call in order to pay is collateral

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function paySellerCollateral(uint _datasetIndex) onlySeller(_datasetIndex) public payable {
        require(now < dataSetArray[_datasetIndex].end - 1 days);
        require(msg.sender == dataSetArray[_datasetIndex].seller);
        require(dataSetArray[_datasetIndex].buyerIndex > 0);

        uint value = calculateSellerDeposit(_datasetIndex);
        require(msg.value == value);
        uint amountToBeDeposited = msg.value.fromUInt()
                                    .mul(hundred16.sub(dataSetArray[_datasetIndex].testerShare.fromUInt())
                                    .div(hundred16)).toUInt();
        dataSetArray[_datasetIndex].ownerDeposit += amountToBeDeposited;
        dataSetArray[_datasetIndex].testPool += (msg.value - amountToBeDeposited);
        dataSetArray[_datasetIndex].coveredDeposits = dataSetArray[_datasetIndex].buyerIndex;
        dataSetArray[_datasetIndex].collateralWasPaid = true;
        dataSetArray[_datasetIndex].neededDeposit = 0;
        emit SellerDeposit(msg.sender, amountToBeDeposited, msg.value - amountToBeDeposited);

    }

    /*
    View function that returns what amount one can bet on an adversarial claim at
    a given time

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function getAdversarialClaimCost(uint _datasetIndex) public view returns (uint) {
        return (calcDepositByIndex(_datasetIndex,dataSetArray[_datasetIndex].advCount)
                .mul(dataSetArray[_datasetIndex].testerShare.fromUInt())
                .div(hundred16)).toUInt();
    }

    /*
    View function that returns the amount one can bet on an adversarial claim at
    a given time

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function getCleanClaimCost(uint _datasetIndex) public view returns (uint) {
        return (calcDepositByIndex(_datasetIndex,dataSetArray[_datasetIndex].cleanCount)
                .mul(dataSetArray[_datasetIndex].testerShare.fromUInt())
                .div(hundred16)).toUInt();
    }

    /*
    Function that submits a claim that the dataset contains adversarial images altered
    using the technique included in the parameter "advMethod"

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function claimAdversarial(uint _datasetIndex,string memory _advMethod) public onlyBuyer(_datasetIndex) payable {
        require(dataSetArray[_datasetIndex].buyers[msg.sender] == 1);
        require(dataSetArray[_datasetIndex].cleanClaims[msg.sender] == 0);
        require(dataSetArray[_datasetIndex].advClaims[msg.sender] == 0);

        bytes16 requiredAmount16 = calcDepositByIndex(_datasetIndex,dataSetArray[_datasetIndex].advCount)
                                    .mul(dataSetArray[_datasetIndex].testerShare.fromUInt())
                                    .div(hundred16);
        require(requiredAmount16.toUInt() == msg.value);

        dataSetArray[_datasetIndex].adversarialMethods.push(_advMethod);
        dataSetArray[_datasetIndex].advClaimantsArray.push(msg.sender);
        dataSetArray[_datasetIndex].advCount++;

        dataSetArray[_datasetIndex].advClaims[msg.sender] =int( dataSetArray[_datasetIndex].advCount);
        dataSetArray[_datasetIndex].totalAdvPool = dataSetArray[_datasetIndex].totalAdvPool
                                                    .add(requiredAmount16);
        emit AdversarialClaim(msg.sender, _advMethod, dataSetArray[_datasetIndex].advCount);

    }


    /*
    Function that submits a claim that the dataset doesnt contain adversarial images

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function claimClean(uint _datasetIndex) public onlyBuyer(_datasetIndex) payable {
        require(dataSetArray[_datasetIndex].buyers[msg.sender] == 1  );
        require(dataSetArray[_datasetIndex].cleanClaims[msg.sender] == 0);
        require(dataSetArray[_datasetIndex].advClaims[msg.sender] == 0);

        bytes16 requiredAmount16 = calcDepositByIndex(_datasetIndex,dataSetArray[_datasetIndex].cleanCount)
                                    .mul(dataSetArray[_datasetIndex].testerShare.fromUInt())
                                    .div(hundred16);
        require(requiredAmount16.toUInt() == msg.value);

        dataSetArray[_datasetIndex].cleanClaimantsArray.push(msg.sender);
        dataSetArray[_datasetIndex].cleanCount++;
        dataSetArray[_datasetIndex].cleanClaims[msg.sender] = int(dataSetArray[_datasetIndex].cleanCount);
        dataSetArray[_datasetIndex].totalCleanPool = dataSetArray[_datasetIndex].totalCleanPool
                                                    .add(requiredAmount16);
        emit CleanClaim(msg.sender, dataSetArray[_datasetIndex].cleanCount);
    }

    /*
    Function that returns the amount required in order for a cleanClamant to be transfered
    to the adversarialClaimants pool.
    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function calcTransferCost(uint _datasetIndex) public onlyBuyer(_datasetIndex) view returns (uint) {
        require(dataSetArray[_datasetIndex].cleanClaims[msg.sender] > 0);
        if( calcBetSizeByIndex(_datasetIndex,uint(dataSetArray[_datasetIndex].cleanClaims[msg.sender]-1)).toUInt()
                > getAdversarialClaimCost(_datasetIndex)){
            return 0;
        } else {
            return getAdversarialClaimCost(_datasetIndex)
                - calcBetSizeByIndex(_datasetIndex,uint(dataSetArray[_datasetIndex].cleanClaims[msg.sender]-1)).toUInt();
        }
    }



    /*
    Function that allows a clean claimant to transfer his claim from a clean one to an adversarial one
    by providing the string associated with the attack method used to generate the adversarial examples
    and, if the cost of the claim is higher than the initial amount paid for the clean claim, the difference
    returned by the calcTransferCost() function.

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function transferToAdv(uint _datasetIndex,string memory _advMethod) public onlyBuyer(_datasetIndex) payable {
        require(now < dataSetArray[_datasetIndex].end - 1 days);
        require(dataSetArray[_datasetIndex].cleanClaims[msg.sender] > 0);
        require(now < dataSetArray[_datasetIndex].end - 1 days);
        uint transferCost = calcTransferCost(_datasetIndex);

        require(msg.value == transferCost);
        uint value = getAdversarialClaimCost(_datasetIndex);

        dataSetArray[_datasetIndex].totalCleanPool = dataSetArray[_datasetIndex].totalCleanPool
                                                    .sub(calcBetSizeByIndex(_datasetIndex,
                                                    uint(dataSetArray[_datasetIndex].cleanClaims[msg.sender]-1)));
        dataSetArray[_datasetIndex].totalAdvPool = dataSetArray[_datasetIndex].totalAdvPool.add(value.fromUInt());
        dataSetArray[_datasetIndex].adversarialMethods.push(_advMethod);
        dataSetArray[_datasetIndex].advClaimantsArray.push(msg.sender);
        dataSetArray[_datasetIndex].advClaims[msg.sender] = int(dataSetArray[_datasetIndex].advCount+ 1);

        dataSetArray[_datasetIndex].cleanCount--;
        dataSetArray[_datasetIndex].advCount++;

        if (transferCost == 0) {
            uint initial_spending = calcBetSizeByIndex(_datasetIndex,
                                    uint(dataSetArray[_datasetIndex].cleanClaims[msg.sender]- 1)).toUInt();
            msg.sender.transfer(initial_spending - value);
        }
        dataSetArray[_datasetIndex].cleanClaims[msg.sender] = 0;
        emit TransferToAdversarial(msg.sender);
    }


    /*
    Function that returns the current opinion of the voters regarding the dataset.
    The function returns 1 if the dataset is considered clean, -1 if it is considered
    adversarial and 0 if the voters cannot reach consensus.
    * First line of the function must be uncommented before deployment
    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function getCurrentDatasetOpinion(uint _datasetIndex) public view returns (int) {
        //   require(now > (end - 1 days));
        //divison by zero checks
        uint cleanCountForRatio = 1;
        if (dataSetArray[_datasetIndex].cleanCount > cleanCountForRatio)
            cleanCountForRatio = dataSetArray[_datasetIndex].cleanCount;
        uint advCountForRatio = 1;
        if (dataSetArray[_datasetIndex].advCount > advCountForRatio)
            advCountForRatio = dataSetArray[_datasetIndex].advCount;
        //Case when dataset was deemed cleen by testers
        if (cleanCountForRatio / advCountForRatio >= 2) {
            return 1;
        } else if (advCountForRatio / cleanCountForRatio >= 2) {
            return - 1;
        } else {
            return 0;
        }
    }


    /*
    Function that computes the amount the seller is allowed to extract from the contract if the dataset is deemed clean
    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function rewardSellerClean(uint _datasetIndex) internal returns(uint){
        return dataSetArray[_datasetIndex].ownerDeposit
                                        + (dataSetArray[_datasetIndex].buyerIndex * dataSetArray[_datasetIndex].price);
    }


    /*
    Function that computes the reward of the buyer if the dataset is deemed clean

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function rewardBuyerClean(uint _datasetIndex) internal returns(uint) {
        require(dataSetArray[_datasetIndex].cleanClaims[msg.sender] > 0);
        uint betSize = calcBetSizeByIndex(_datasetIndex,
            uint(dataSetArray[_datasetIndex].cleanClaims[msg.sender] - 1)).toUInt();
        uint transferValue = 0;
        if(dataSetArray[_datasetIndex].thirdPartyInvoked == false){

            transferValue = (betSize.fromUInt()
                            .div(dataSetArray[_datasetIndex].totalCleanPool)
                            .mul(dataSetArray[_datasetIndex].testPool.fromUInt()
                            .add(dataSetArray[_datasetIndex].totalAdvPool))).toUInt() + betSize;
        }
        else {
             transferValue = (betSize.fromUInt()
                            .div(dataSetArray[_datasetIndex].totalCleanPool)
                            .mul(dataSetArray[_datasetIndex].testPool.fromUInt())).toUInt() + betSize;
        }
        return transferValue;

    }
    /*
    Function that computes the reward of the buyer in the case that the dataset is deemed adversarial

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function rewardBuyerAdversarial(uint _datasetIndex) internal returns(uint){
        require(dataSetArray[_datasetIndex].buyers[msg.sender] == 1);
        msg.sender.transfer(dataSetArray[_datasetIndex].price);
        emit BuyerRefund(_datasetIndex, msg.sender);
        uint transferValue=0;
        if (dataSetArray[_datasetIndex].advClaims[msg.sender] > 0) {
            uint betSize = calcBetSizeByIndex(_datasetIndex,
                uint(dataSetArray[_datasetIndex].advClaims[msg.sender] - 1)).toUInt();

            if(dataSetArray[_datasetIndex].thirdPartyInvoked == false){
             transferValue = betSize.fromUInt()
                                .div(dataSetArray[_datasetIndex].totalAdvPool)
                                .mul((dataSetArray[_datasetIndex].testPool.fromUInt()
                                .add(dataSetArray[_datasetIndex].ownerDeposit.fromUInt()
                                .add(dataSetArray[_datasetIndex].totalCleanPool)))).toUInt() + betSize;
        }
        else {
        transferValue = betSize.fromUInt()
                                .div(dataSetArray[_datasetIndex].totalAdvPool)
                                .mul((dataSetArray[_datasetIndex].testPool.fromUInt()
                                .add(dataSetArray[_datasetIndex].ownerDeposit.fromUInt()
                                ))).toUInt() + betSize;
        }


        }
        return transferValue;


    }


    /*
    Internal function used to calculate the value each buyer must receive in case the seller does not pay his collateral

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function refundBuyer(uint _datasetIndex) internal returns(uint){
        require(dataSetArray[_datasetIndex].buyers[msg.sender] == 1);
        dataSetArray[_datasetIndex].buyers[msg.sender] = 0;
        msg.sender.transfer(dataSetArray[_datasetIndex].price);
        emit BuyerRefund(_datasetIndex, msg.sender);
        uint transferValue;
        if (dataSetArray[_datasetIndex].advClaims[msg.sender] > 0) {
            uint betSize = calcBetSizeByIndex(_datasetIndex,
                uint(dataSetArray[_datasetIndex].advClaims[msg.sender])).toUInt();
             transferValue = betSize.fromUInt()
                                .div(dataSetArray[_datasetIndex].totalAdvPool)
                                .mul((dataSetArray[_datasetIndex].testPool.fromUInt()
                                .add(dataSetArray[_datasetIndex].ownerDeposit.fromUInt()
                                .add(dataSetArray[_datasetIndex].totalCleanPool)))).toUInt() + betSize;

        }
        return transferValue;

    }



    /*
    Function that allows both buyers and sellers to extract their reward after the voting has finalised
    * also used to invoke the third party when a decision cannot be taken through voting
    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function getReward(uint _datasetIndex) public payable{
        if(dataSetArray[_datasetIndex].thirdPartyInvoked == false){
            if(dataSetArray[_datasetIndex].collateralWasPaid == true){
                if (getCurrentDatasetOpinion(_datasetIndex) == 1){
                    if(msg.sender == dataSetArray[_datasetIndex].seller){
                        uint transferValue = rewardSellerClean(_datasetIndex);
                        dataSetArray[_datasetIndex].seller.transfer(transferValue);
                        emit SellerWithdrawal(_datasetIndex,msg.sender, transferValue);
                        return;
                    }
                    else{
                        uint transferValue = rewardBuyerClean(_datasetIndex);
                        msg.sender.transfer(transferValue);
                        emit ClaimantWithdrawal(_datasetIndex, msg.sender, transferValue);
                        dataSetArray[_datasetIndex].cleanClaims[msg.sender] = 0;
                        return;
                    }
                }
                else if(getCurrentDatasetOpinion(_datasetIndex) == -1){
                        uint transferValue = rewardBuyerAdversarial(_datasetIndex);
                    msg.sender.transfer(transferValue);
            emit ClaimantWithdrawal(_datasetIndex, msg.sender, transferValue);
        dataSetArray[_datasetIndex].buyers[msg.sender] = 0;
                        return;
                }
                else{
                     dataSetArray[_datasetIndex].thirdPartyInvoked = true;
                    emit ThirdPartyInvocation(_datasetIndex,msg.sender);
                }

            }
            else{
                uint transferValue = refundBuyer(_datasetIndex);
                msg.sender.transfer(transferValue);
                emit ClaimantWithdrawal(_datasetIndex, msg.sender, transferValue);

                return;
            }
        }
        else if(dataSetArray[_datasetIndex].thirdPartyInvoked == true){
            if(dataSetArray[_datasetIndex].decision == 1){
                if(msg.sender == dataSetArray[_datasetIndex].seller){
                     uint transferValue = rewardSellerClean(_datasetIndex);
                     dataSetArray[_datasetIndex].seller.transfer(transferValue);
                     emit SellerWithdrawal(_datasetIndex,msg.sender, transferValue);
                     return;
                }
                else if(msg.sender != dataSetArray[_datasetIndex].thirdPartyAddress){
                   uint transferValue =  rewardBuyerClean(_datasetIndex);
                   msg.sender.transfer(transferValue);
                   emit ClaimantWithdrawal(_datasetIndex, msg.sender, transferValue);
                   dataSetArray[_datasetIndex].cleanClaims[msg.sender] = 0;
                   return;
                }
            }
            else{
                if(msg.sender == dataSetArray[_datasetIndex].thirdPartyAddress){
                     //msg.sender.transfer(dataSetArray[_datasetIndex].totalCleanPool.toUInt());

                     emit ThirdPartyPayment(_datasetIndex,msg.sender, dataSetArray[_datasetIndex].totalCleanPool.toUInt());
                     emit ThirdPartyDecision(_datasetIndex, msg.sender, - 1);
                     return;
                }
                else{uint transferValue = rewardBuyerAdversarial(_datasetIndex);
                    msg.sender.transfer(transferValue);
            emit ClaimantWithdrawal(_datasetIndex, msg.sender, transferValue);
        dataSetArray[_datasetIndex].buyers[msg.sender] = 0;
                return;
                }
            }
        }

    }

    /*
    Function that is called by the third party in order to deem the dataset as clean
    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function thirdPartyCleanDecision(uint _datasetIndex) onlyThirdParty(_datasetIndex) public payable {
        require(dataSetArray[_datasetIndex].thirdPartyInvoked == true);
        require( msg.sender == dataSetArray[_datasetIndex].thirdPartyAddress);
        dataSetArray[_datasetIndex].decision=1;
        msg.sender.transfer(dataSetArray[_datasetIndex].totalAdvPool.toUInt());
        if(dataSetArray[_datasetIndex].forcedThirdInvocation == true){
                        msg.sender.transfer(dataSetArray[_datasetIndex].totalAdvPool.toUInt());
                    }
        emit ThirdPartyDecision(_datasetIndex,msg.sender, 1);

    }



    /*
    Function that is called by the third party in order to deem the dataset as adversarial

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function thirdPartyAdversarialDecision(uint _datasetIndex) onlyThirdParty(_datasetIndex) public payable{
        require(dataSetArray[_datasetIndex].thirdPartyInvoked == true);
        require( msg.sender == dataSetArray[_datasetIndex].thirdPartyAddress);
        dataSetArray[_datasetIndex].decision=-1;
        msg.sender.transfer(dataSetArray[_datasetIndex].totalCleanPool.toUInt());
        if(dataSetArray[_datasetIndex].forcedThirdInvocation == true){
                         msg.sender.transfer(dataSetArray[_datasetIndex].totalAdvPool.toUInt());
                     }
        emit ThirdPartyDecision(_datasetIndex,msg.sender, -1);
    }


    /*
    Function that returns the amount of currency the seller must deposit in order to invoke the third party by force

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function getForcedInvocationCost(uint _datasetIndex) public view returns (uint){
        return dataSetArray[_datasetIndex].totalAdvPool.toUInt();
    }

    /*
    Function that seller must call in order to invoke the third party by force
    *first line of the function must be uncommented before deployment

    Parameters:
        - _datasetIndex: the primary key used to identify each dataset in the contract
    */
    function invokeThirdParty(uint _datasetIndex) public onlySeller(_datasetIndex) payable {
        //require(now > end - 1 days && now < end);
        require( msg.value == dataSetArray[_datasetIndex].totalAdvPool.toUInt());
        require( msg.sender == dataSetArray[_datasetIndex].seller);
        dataSetArray[_datasetIndex].forcedThirdInvocation = true;
        dataSetArray[_datasetIndex].thirdPartyInvoked = true;
        emit ThirdPartyInvocation(_datasetIndex,msg.sender);
    }

    /*
    Default fallback function
    */
    function() external payable {
    }

}
