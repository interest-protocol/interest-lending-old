// SPDX-License-Identifier: CC-BY-4.0
pragma solidity 0.8.15;

library ERC20Lib {
    bytes4 private constant SIG_DECIMALS = 0x313ce567; // decimals()

    /**
     * @notice Provides a safe ERC20.decimals version which returns '18' as fallback value.
     * @param token The address of the ERC-20 token contract.
     * @return (uint8) Token decimals.
     * @dev reverts if the `token` has no code in it.
     */
    function safeDecimals(address token) internal view returns (uint8) {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            let size := extcodesize(token)

            if iszero(size) {
                revert(0, 0)
            }
        }

        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(SIG_DECIMALS)
        );

        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }
}
