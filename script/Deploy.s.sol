// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "forge-std/Script.sol";

import {ChainlogAbstract} from "dss-interfaces/dss/ChainlogAbstract.sol";
import {VatAbstract} from "dss-interfaces/dss/VatAbstract.sol";
import {IlkRegistryAbstract} from "dss-interfaces/dss/IlkRegistryAbstract.sol";
import {JugAbstract} from "dss-interfaces/dss/JugAbstract.sol";
import {SpotAbstract} from "dss-interfaces/dss/SpotAbstract.sol";
import {DaiAbstract} from "dss-interfaces/dss/DaiAbstract.sol";
import {RwaLiquidationOracleAbstract} from "dss-interfaces/dss/mip21/RwaLiquidationOracleAbstract.sol";
import {RwaTokenFactoryAbstract} from "dss-interfaces/dss/mip21/RwaTokenFactoryAbstract.sol";

import {RwaRegistry} from "../src/RwaRegistry.sol";

contract DeployRwaRegistry is Script {
    ChainlogAbstract internal chainlog;
    address internal mcdPauseProxy;
    address internal rwaLiquidationOracle;

    RwaRegistry internal reg;

    constructor() {
        chainlog = ChainlogAbstract(vm.envAddress("CHANGELOG"));
        mcdPauseProxy = chainlog.getAddress("MCD_PAUSE_PROXY");
        rwaLiquidationOracle = chainlog.getAddress("MIP21_LIQUIDATION_ORACLE");
    }

    function run() external returns (address) {
        vm.startBroadcast();

        reg = new RwaRegistry();

        _addRWA008A();
        _addRWA009A();

        reg.rely(mcdPauseProxy);
        reg.deny(msg.sender);

        vm.stopBroadcast();

        return address(reg);
    }

    function _addRWA008A() internal {
        bytes32[] memory names = new bytes32[](4);
        names[0] = URN;
        names[1] = OUTPUT_CONDUIT;
        names[2] = INPUT_CONDUIT;
        names[3] = LIQUIDATION_ORACLE;

        address[] memory addrs = new address[](4);
        addrs[0] = chainlog.getAddress("RWA008_A_URN");
        addrs[1] = chainlog.getAddress("RWA008_A_OUTPUT_CONDUIT");
        addrs[2] = chainlog.getAddress("RWA008_A_INPUT_CONDUIT");
        addrs[3] = rwaLiquidationOracle;

        uint8[] memory variants = new uint8[](4);
        variants[0] = 2; // RwaUrn2
        variants[1] = 2; // RwaOutputConduit2
        variants[2] = 2; // RwaInputConduit2
        variants[3] = 1; // RwaLiquidationOracle

        reg.add("RWA008-A", names, addrs, variants);
    }

    function _addRWA009A() internal {
        bytes32[] memory names = new bytes32[](4);
        names[0] = URN;
        names[1] = JAR;
        names[2] = OUTPUT_CONDUIT;
        names[3] = LIQUIDATION_ORACLE;

        address[] memory addrs = new address[](4);
        addrs[0] = chainlog.getAddress("RWA009_A_URN");
        addrs[1] = chainlog.getAddress("RWA009_A_JAR");
        addrs[2] = chainlog.getAddress("RWA009_A_OUTPUT_CONDUIT");
        addrs[3] = rwaLiquidationOracle;

        uint8[] memory variants = new uint8[](4);
        variants[0] = 2; // RwaUrn2
        variants[1] = 1; // RwaJar
        variants[2] = type(uint8).max; // Regular address
        variants[3] = 1; // RwaLiquidationOracle

        reg.add("RWA009-A", names, addrs, variants);
    }

    bytes32 internal constant URN = "urn";
    bytes32 internal constant JAR = "jar";
    bytes32 internal constant OUTPUT_CONDUIT = "outputConduit";
    bytes32 internal constant INPUT_CONDUIT = "inputConduit";
    bytes32 internal constant LIQUIDATION_ORACLE = "liquidationOracle";
}
