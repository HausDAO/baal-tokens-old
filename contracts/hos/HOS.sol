// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@gnosis.pm/zodiac/contracts/factory/ModuleProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "@daohaus/baal-contracts/contracts/interfaces/IBaal.sol";
import "@daohaus/baal-contracts/contracts/interfaces/IBaalToken.sol";

import "../interfaces/IShaman.sol";
import "../interfaces/IBaalAndVaultSummoner.sol";

contract SuperSummoner is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    IBaalAndVaultSummoner public _baalSummoner;

    event SetSummoner(address summoner);

    event DeployBaalToken(address tokenAddress);

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @dev Sets the address of the BaalSummoner contract (vault summoner hos)
     * @param baalAndVaultSummoner The address of the BaalSummoner contract
     */
    function setUp(address baalAndVaultSummoner) public onlyOwner {
        require(baalAndVaultSummoner != address(0), "zero address");
        _baalSummoner = IBaalAndVaultSummoner(baalAndVaultSummoner); //vault summoner
        emit SetSummoner(baalAndVaultSummoner);
    }

    /**
     * @dev Summon a new Baal contract with a new set of tokens
     * @param initializationLootTokenParams The parameters for deploying the token
     * @param initializationShareTokenParams The parameters for deploying the token
     * @param initializationShamanParams  The parameters for deploying the shaman
     * @param postInitializationActions The actions to be performed after the initialization
     */
    function summonBaalFromReferrer(
        bytes calldata initializationLootTokenParams,
        bytes calldata initializationShareTokenParams,
        bytes calldata initializationShamanParams,
        bytes[] memory postInitializationActions,
        uint256 saltNounce,
        address safeAddr,
        address forwarder
    ) external {
        // summon tokens
        address lootToken = deployToken(initializationLootTokenParams);

        address sharesToken = deployToken(initializationShareTokenParams);

        (bytes[] memory amendedPostInitActions, IShaman shaman) = deployShaman(
            postInitializationActions,
            initializationShamanParams
        );

        // summon baal with new tokens
        (address baal, address vault) = _baalSummoner.summonBaalAndVault(
            abi.encode(
                IBaalToken(sharesToken).name(),
                IBaalToken(sharesToken).symbol(),
                safeAddr,
                forwarder, // forwarder
                lootToken,
                sharesToken
            ),
            amendedPostInitActions,
            saltNounce, // nonce
            bytes32(bytes("DHSuperSummoner")), // referrer
            "sidecar"
        );

        // init shaman here
        // shaman setup with dao address, vault address and initShamanParams
        setUpShaman(address(shaman), baal, vault, initializationShamanParams);

        // TODO: mint tokens to vault here
        // should this address be configurable?

        // change token ownership to baal
        IBaalToken(lootToken).transferOwnership(address(baal));
        IBaalToken(sharesToken).transferOwnership(address(baal));


    }

    /**
     * @dev deployToken
     * @param initializationParams The parameters for deploying the token
     */
    function deployToken(
        bytes calldata initializationParams
    ) internal returns (address token) {
        // todo: support bring your own token
        // maybe if initPrams is empty, then use template as token
        (address template, bytes memory initParams) = abi.decode(
            initializationParams,
            (address, bytes)
        );

        // ERC1967 could be upgradable
        token = address(
            new ERC1967Proxy(
                template,
                abi.encodeWithSelector(
                    IBaalToken(template).setUp.selector,
                    initParams
                )
            )
        );

        emit DeployBaalToken(token);
    }

    function deployShaman(
        bytes[] memory postInitializationActions,
        bytes memory initializationShamanParams
    ) internal returns (bytes[] memory amendedPostInitActions, IShaman shaman) {
        // summon shaman
        // (address template, uint256 permissions, bytes memory initParams)
        (address shamanTemplate, uint256 perm, ) = abi.decode(
            initializationShamanParams,
            (address, uint256, bytes)
        );
        // Clones because it should not need to be upgradable
        shaman = IShaman(payable(Clones.clone(shamanTemplate)));

        // amend postInitializationActions to include shaman setup
        amendedPostInitActions = new bytes[](
            postInitializationActions.length + 1
        );
        address[] memory shamans = new address[](1);
        uint256[] memory permissions = new uint256[](1);
        // Clones because it should not need to be upgradable
        shamans[0] = address(shaman);
        permissions[0] = perm;

        amendedPostInitActions[0] = abi.encodeWithSignature(
            "setShaman(address[],uint256[])",
            shamans,
            permissions
        );
        // copy over the rest of the actions
        for (uint256 i = 1; i < postInitializationActions.length; i++) {
            amendedPostInitActions[i] = postInitializationActions[i];
        }
    }

    function setUpShaman(
        address shaman,
        address baal,
        address vault,
        bytes memory initializationShamanParams
    ) internal {
        (, , bytes memory initShamanParams) = abi.decode(
            initializationShamanParams,
            (address, uint256, bytes)
        );
        IShaman(shaman).setup(baal, vault, initShamanParams);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
