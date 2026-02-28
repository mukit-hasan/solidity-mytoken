// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

library Fee {
    function calculateFee(
        uint256 amount,
        uint256 _feeBps
    ) public pure returns (uint256 afterFee, uint256 feeAmount) {
        feeAmount = (amount * _feeBps) / 10000;
        afterFee = amount - feeAmount;
    }
}

contract MyToken is ERC20, ReentrancyGuard {
    enum State {
        Waiting,
        Active,
        Paused
    }
    State public state;
    address public owner;
    uint256 public minBuy;
    uint256 public feeBps;
    uint256 public collectedFee;
    uint256 public maxSupply;

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner can do that");
        _;
    }

    modifier IsActive() {
        require(state == State.Active, "Is not Active");
        _;
    }

    constructor(uint256 _minBuy, uint256 _feeBps) ERC20("My Token", "MTK") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
        maxSupply = 10_000_000 * 10 ** decimals();
        owner = msg.sender;
        state = State.Waiting;
        minBuy = _minBuy;
        feeBps = _feeBps;
    }

    event TokensPurchased(
        address indexed buyer,
        uint256 ethSpent,
        uint256 tokensReceived
    );
    event TokensSold(
        address indexed seller,
        uint256 tokensSold,
        uint256 ethReceived
    );
    event FeeUpdated(uint256 newFeeBps);
    event FeesWithdrawn(uint256 amount);
    event StateUpdated(State newState);
    event ETHWithdrawn(uint256 amount);
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );
    event MinBuyUpdated(uint256 newMinBuy);

    function mint(address _address, uint256 amount) external onlyOwner {
        uint256 mintAmount = amount * 10 ** decimals();
        require(totalSupply() + mintAmount <= maxSupply, "max supply reached");
        super._mint(_address, mintAmount);
    }

    function burn(uint256 amount) external onlyOwner {
        super._burn(msg.sender, amount * 10 ** decimals());
    }

    function depositToken(uint256 amountTokens) external onlyOwner {
        uint256 amount = amountTokens * 10 ** decimals();
        _transfer(msg.sender, address(this), amount);
    }

    function depositTokenUnits(uint256 tokenUnits) external onlyOwner {
        _transfer(msg.sender, address(this), tokenUnits);
    }

    function depositEtr() external payable onlyOwner {
        require(msg.value > 0, "Send Etr");
    }

    function getTokenPrice() public view returns (uint256) {
        uint256 tokenReserve = balanceOf(address(this));
        uint256 ethReserve = address(this).balance;
        if (ethReserve == 0 || tokenReserve == 0) return 0;
        return (tokenReserve * 1e18) / ethReserve;
    }

    function buyToken(
        uint256 minTokensOut
    ) external payable nonReentrant IsActive {
        require(msg.value > 0, "send ETH");
        require(msg.value >= minBuy, "below minimum buy");
        uint256 ethReserve = address(this).balance - msg.value;

        (uint256 ethAfterFee, uint256 fee) = Fee.calculateFee(
            msg.value,
            feeBps
        );
        uint256 tokenReserve = balanceOf(address(this));
        require(ethReserve > 0, "no liquidity, contact owner");
        uint256 tokensOut = (ethAfterFee * tokenReserve) /
            (ethReserve + ethAfterFee);
        require(tokensOut >= minTokensOut, "slippage too high");
        require(tokensOut > 0, "too small");
        require(tokenReserve >= tokensOut, "not enough tokens");
        _transfer(address(this), msg.sender, tokensOut);
        collectedFee += fee;
        emit TokensPurchased(msg.sender, msg.value, tokensOut);
    }

    function sellToken(
        uint256 amountTokens,
        uint256 minEthOut
    ) external nonReentrant IsActive {
        uint256 tokenAmount = amountTokens * 10 ** decimals();
        require(balanceOf(msg.sender) >= tokenAmount, "not enough tokens");
        uint256 tokenReserve = balanceOf(address(this));
        uint256 ethReserve = address(this).balance;
        uint256 ethOut = (tokenAmount * ethReserve) /
            (tokenReserve + tokenAmount);
        (uint256 ethAfterFee, uint256 fee) = Fee.calculateFee(ethOut, feeBps);
        require(ethAfterFee > 0, "too small");
        require(ethAfterFee >= minEthOut, "slippage too high");
        require(address(this).balance >= ethAfterFee, "contract lacks ETH");
        _transfer(msg.sender, address(this), tokenAmount);
        (bool ok, ) = payable(msg.sender).call{value: ethAfterFee}("");
        require(ok, "ETH payout failed");
        collectedFee += fee;
        emit TokensSold(msg.sender, tokenAmount, ethAfterFee);
    }

    function sellTokenUnits(
        uint256 tokenUnits,
        uint256 minEthOut
    ) external nonReentrant IsActive {
        require(tokenUnits > 0, "amount=0");
        require(balanceOf(msg.sender) >= tokenUnits, "not enough tokens");
        uint256 tokenReserve = balanceOf(address(this));
        uint256 ethReserve = address(this).balance;
        uint256 weiToPay = (tokenUnits * ethReserve) /
            (tokenReserve + tokenUnits);
        (uint256 ethAfterFee, uint256 fee) = Fee.calculateFee(weiToPay, feeBps);
        require(ethAfterFee > 0, "too small");
        require(ethAfterFee >= minEthOut, "slippage too high");
        require(address(this).balance >= ethAfterFee, "contract lacks ETH");
        _transfer(msg.sender, address(this), tokenUnits);
        (bool ok, ) = payable(msg.sender).call{value: ethAfterFee}("");
        require(ok, "ETH payout failed");
        collectedFee += fee;
        emit TokensSold(msg.sender, tokenUnits, ethAfterFee);
    }

    function withdrawEthFee() external onlyOwner nonReentrant {
        uint256 feeToCollect = collectedFee;
        require(feeToCollect > 0, "No fee to collect");
        require(address(this).balance >= feeToCollect, "not enough ETH");
        collectedFee = 0;
        (bool ok, ) = payable(owner).call{value: feeToCollect}("");
        require(ok, "withdraw failed");
        emit FeesWithdrawn(feeToCollect);
    }

    function withdrawETH(uint256 amountWei) external onlyOwner nonReentrant {
        require(
            address(this).balance >= amountWei + collectedFee,
            "would drain fees"
        );
        require(address(this).balance >= amountWei, "not enough ETH");
        (bool ok, ) = payable(owner).call{value: amountWei}("");
        require(ok, "withdraw failed");
        emit ETHWithdrawn(amountWei);
    }

    function withdrawUnsoldTokens(uint256 tokenUnits) external onlyOwner {
        _transfer(address(this), owner, tokenUnits);
    }

    function updateState(uint256 _state) external onlyOwner {
        require(_state <= 2, "invalid state");
        state = State(_state);
        emit StateUpdated(State(_state));
    }

    function setFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "max fee is 1000 mean 10%");
        feeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    function setMinBuy(uint256 _minBuy) external onlyOwner {
        minBuy = _minBuy;
        emit MinBuyUpdated(_minBuy);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "zero address");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }
}
