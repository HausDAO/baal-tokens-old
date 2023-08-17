// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import "@daohaus/baal-contracts/contracts/interfaces/IBaal.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

// import "hardhat/console.sol";

// tribute eth for loot or shares
contract SimpleEthOnboarderShaman is ReentrancyGuard, Initializable {

    event ObReceived(
        address indexed contributorAddress,
        uint256 amount,
        uint256 isShares,
        address baal,
        address vault
    );

    uint256 public expiry;
    uint256 public multiply;
    uint256 public minTribute;
    bool public isShares;

    IBaal public baal;
    address vault;

    constructor() initializer {}

    function init(
        address _moloch, // DAO address
        address _vault,  // recipient vault
        uint256 _expiry, // expiery date
        uint256 _multiply, // multiply eth by this
        uint256 _minTribute, // min eth to send
        bool _isShares // mint shares or loot

    ) initializer external {
        baal = IBaal(_moloch);
        vault = _vault;
        expiry = _expiry;
        multiply = _multiply;
        minTribute = _minTribute;
        isShares = _isShares;

    }

    function _mintTokens(address to, uint256 amount) private {
        address[] memory _receivers = new address[](1);
        _receivers[0] = to;

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = amount;

        if (isShares) {
            baal.mintShares(_receivers, _amounts);
        } else {
            baal.mintLoot(_receivers, _amounts);
        }
    }

    // tribute eth for loot or shares
    // must meet minimum tribute
    // fees are sent to the cuts addresses
    // eth is sent to the DAO
    // loot or shares are minted to the sender
    function onboarder() payable public nonReentrant {
        require(address(baal) != address(0), "!init");
        require(expiry > block.timestamp, "expiry");
        require(baal.isManager(address(this)), "Shaman not manager");

        require(msg.value >= minTribute, "!minTribute");
        
        // mint loot or shares minus any fees
        uint256 _shares = msg.value * multiply;

        // transfer funds to vault
        (bool success, ) = vault.call{value: msg.value}(
            ""
        );
        require(success, "Transfer failed");

        _mintTokens(msg.sender, _shares);

        emit ObReceived(
            msg.sender,
            msg.value,
            _shares,
            address(baal),
            vault
        );
    }

    receive() external payable {
        onboarder();
    }

}