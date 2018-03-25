pragma solidity ^0.4.16;

/**
 * TokenERC223 standard. The ERC20 token standard has a fundamental issue as it has not addressed the token fallback possibility.
 * Bob sends X tokens to Alices Ethereum address which may be a non-receiving token address and if it is, X tokens sent are lost forever.
 * Not until recently, Dexeran(Github alias) an Ethereum Classic (ETC) developer, used some inline assembly(within solidity) to fix this issue.
 * It is implemented such that there may be a token fallback to the token sender just as the case is for sending Ether accross Ether addresses.
 *
 */

 /**
  * Math operations with safety checks
  */
 library SafeMath {
   function mul(uint256 a, uint256 b) public pure returns (uint256) {
     uint256 c = a * b;
     assert(a == 0 || c / a == b);
     return c;
   }

   function div(uint256 a, uint256 b) public pure returns (uint256) {
     // assert(b > 0); // Solidity automatically throws when dividing by 0
     uint256 c = a / b;
     // assert(a == b * c + a % b); // There is no case in which this doesn't hold
     return c;
   }

   function sub(uint256 a, uint256 b) public pure returns (uint256) {
     assert(b <= a);
     return a - b;
   }

   function add(uint256 a, uint256 b) public pure returns (uint256) {
     uint256 c = a + b;
     assert(c >= a);
     return c;
   }

   function max64(uint64 a, uint64 b) public pure returns (uint64) {
     return a >= b ? a : b;
   }

   function min64(uint64 a, uint64 b) public pure returns (uint64) {
     return a < b ? a : b;
   }

   function max256(uint256 a, uint256 b) public pure returns (uint256) {
     return a >= b ? a : b;
   }

   function min256(uint256 a, uint256 b) internal returns (uint256) {
     return a < b ? a : b;
   }

 }

contract owned {
    address public owner;

    event LogOwnershipTransfer(address indexed newOwner);

    function owned() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
        emit LogOwnershipTransfer(newOwner);
    }
}

interface tokenRecipient {
  //Kindly implement the functions of this interface as you may like
  function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) external;
}

interface ERC223Receiver {
  //Kindly implement the functions of this interface as you may like
  function tokenFallback(address indexed _from, uint256 _value, bytes _data);
}

contract TokenERC223 {
   //We will use the imported SafeMath library to check for overflows/underflows
    using SafeMath for uint256;

    // Public variables of the token
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    // 18 decimals is the strongly suggested default, avoid changing it
    uint256 public totalSupply;

    // This creates an array with all balances
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    // This generates a public event on the blockchain that will notify clients
    event Transfer(address indexed from, address indexed to, uint256 value);

    // This notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);

    /**
     * Constrctor function
     *
     * Initializes contract with initial supply tokens to the creator of the contract
     */
    function TokenERC20(
        uint256 initialSupply,
        string tokenName,
        string tokenSymbol
    ) public {
        totalSupply = initialSupply * 10 ** uint256(decimals);  // Update total supply with the decimal amount
        balanceOf[msg.sender] = totalSupply;                // Give the creator all initial tokens
        name = tokenName;                                   // Set the name for display purposes
        symbol = tokenSymbol;                               // Set the symbol for display purposes
    }

    /**
     * Internal transfer, only can be called by this contract
     */
    function transfer(address _from, address _to, uint _value, bytes _extraData) public {
        // Prevent transfer to 0x0 address. Use burn() instead and the sender has enough
        require(_to != 0x0 && balanceOf[_from] >= _value);
        // Check for overflows
        require(balanceOf[_to].add(_value) > balanceOf[_to]);

        uint codelength;

        balanceOf[msg.sender]=balanceOf[msg.sender].sub(_value);
        balanceOf[_to]=balanceOf[_to].add(_value);

        //Recieve the code size of _to, this needs assembly
        assembly{
            codelength:=extcodesize(_to)
        }

        if(codelength>0){
            ERC223Receiver receiver=ERC223Receiver(_to);
            receiver.tokenFallback(msg.sender,_value, _data);
        }

        emit Transfer(_from, _to, _value);
    }

    /**
     * Transfer tokens from other address
     *
     * Send `_value` tokens to `_to` in behalf of `_from`
     *
     * @param _from The address of the sender
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);     // Check allowance
        allowance[_from][msg.sender].sub(_value);
        transfer(_from, _to, _value);
        return true;
    }

    /**
     * Set allowance for other address
     *
     * Allows `_spender` to spend no more than `_value` tokens in your behalf
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     */
    function approve(address _spender, uint256 _value) public
        returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    /**
     * Set allowance for other address and notify
     *
     * Allows `_spender` to spend no more than `_value` tokens in your behalf, and then ping the contract about it
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     * @param _extraData some extra information to send to the approved contract
     */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
        public
        returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    /**
     * Destroy tokens
     *
     * Remove `_value` tokens from the system irreversibly
     *
     * @param _value the amount of money to burn
     */
    function burn(uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);   // Check if the sender has enough
        balanceOf[msg.sender].sub(_value);            // Subtract from the sender
        totalSupply.sub(_value);                      // Updates totalSupply
        Burn(msg.sender, _value);
        return true;
    }

    /**
     * Destroy tokens from other account
     *
     * Remove `_value` tokens from the system irreversibly on behalf of `_from`.
     *
     * @param _from the address of the sender
     * @param _value the amount of money to burn
     */
    function burnFrom(address _from, uint256 _value) public returns (bool success) {
        require(balanceOf[_from] >= _value);                // Check if the targeted balance is enough
        require(_value <= allowance[_from][msg.sender]);    // Check allowance
        balanceOf[_from].sub(_value);                         // Subtract from the targeted balance
        allowance[_from][msg.sender].sub(_value);             // Subtract from the sender's allowance
        totalSupply.sub(_value);                              // Update totalSupply
        Burn(_from, _value);
        return true;
    }
}

/******************************************/
/*       ADVANCED TOKEN STARTS HERE       */
/******************************************/

contract MyAdvancedToken is owned, TokenERC223 {

    using SafeMath for uint256;

    uint256 public sellPrice;
    uint256 public buyPrice;

    mapping (address => bool) public frozenAccount;

    /* This generates a public event on the blockchain that will notify clients */
    event FrozenFunds(address target, bool frozen);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    function MyAdvancedToken(
        uint256 initialSupply,
        string tokenName,
        string tokenSymbol
    ) TokenERC20(initialSupply, tokenName, tokenSymbol) public {}

    /// @notice Create `mintedAmount` tokens and send it to `target`
    /// @param target Address to receive the tokens
    /// @param mintedAmount the amount of tokens it will receive
    function mintToken(address target, uint256 mintedAmount) onlyOwner public {
        balanceOf[target].add(mintedAmount);
        totalSupply.add(mintedAmount);
        Transfer(0, this, mintedAmount);
        Transfer(this, target, mintedAmount);
    }

    /// @notice `freeze? Prevent | Allow` `target` from sending & receiving tokens
    /// @param target Address to be frozen
    /// @param freeze either to freeze it or not
    function freezeAccount(address target, bool freeze) onlyOwner public {
        frozenAccount[target] = freeze;
        FrozenFunds(target, freeze);
    }

    /// @notice Allow users to buy tokens for `newBuyPrice` eth and sell tokens for `newSellPrice` eth
    /// @param newSellPrice Price the users can sell to the contract
    /// @param newBuyPrice Price users can buy from the contract
    function setPrices(uint256 newSellPrice, uint256 newBuyPrice) onlyOwner public {
        sellPrice = newSellPrice;
        buyPrice = newBuyPrice;
    }

    /// @notice Buy tokens from contract by sending ether
    function buy() payable public {
        uint amount = msg.value.div(buyPrice);               // calculates the amount
        transfer(this, msg.sender, amount, bytes _extraData);              // makes the transfers
    }

    /// @notice Sell `amount` tokens to contract
    /// @param amount amount of tokens to be sold
    function sell(uint256 amount) public {
        require(this.balance >= amount.mul(sellPrice));      // checks if the contract has enough ether to buy
        transfer(msg.sender, this, amount);              // makes the transfers
        msg.sender.transfer(amount.mul(sellPrice));          // sends ether to the seller. It's important to do this last to avoid recursion attacks
    }
}
