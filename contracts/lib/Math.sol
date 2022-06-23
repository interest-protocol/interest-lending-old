// SPDX-License-Identifier: CC-BY-4.0
pragma solidity 0.8.15;

/**
 * @notice We copied from https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol
 * @notice We modified line 67 per this post https://ethereum.stackexchange.com/questions/96642/unary-operator-cannot-be-applied-to-type-uint256
 */
// taken from https://medium.com/coinmonks/math-in-solidity-part-3-percents-and-proportions-4db014e080b1
// license is CC-BY-4.0
library Math {
    // Scalar of most ERC20 tokens
    uint256 private constant WAD = 1e18;
    uint256 private constant RAY = 1e27;
    uint256 private constant WAD_RAY_RATIO = 1e9;

    /**
     * @dev Function ensures that the return value keeps the right mantissa
     */
    function wadMul(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDiv(x, y, WAD);
    }

    /**
     * @dev Function ensures that the return value keeps the right mantissa
     */
    function wadDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDiv(x, WAD, y);
    }

    /**
     * @dev Function ensures that the return value keeps the right mantissa
     */
    function rayMul(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDiv(x, y, RAY);
    }

    /**
     * @dev Function ensures that the return value keeps the right mantissa
     */
    function rayDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDiv(x, RAY, y);
    }

    function toWad(uint256 amount, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            if eq(decimals, 18) {
                mstore(0x40, amount)
                return(0x40, 0x20)
            }

            if gt(18, decimals) {
                let r := mul(amount, exp(10, sub(18, decimals)))

                // Protect agaisnt overflow
                if iszero(eq(div(r, exp(10, sub(18, decimals))), amount)) {
                    revert(0, 0)
                }

                mstore(0x40, r)
                return(0x40, 0x20)
            }

            mstore(0x40, div(amount, exp(10, sub(decimals, 18))))
            return(0x40, 0x20)
        }
    }

    function wadToRay(uint256 x) internal pure returns (uint256 y) {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            y := mul(x, WAD_RAY_RATIO)

            // Protect agaisnt overflow
            if iszero(eq(div(y, WAD_RAY_RATIO), x)) {
                revert(0, 0)
            }
        }
    }

    /**
     *@notice This function always rounds down
     */
    function rayToWad(uint256 x) internal pure returns (uint256 y) {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            y := div(x, WAD_RAY_RATIO)
        }
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256 c) {
        //solhint-disable-next-line no-inline-assembly
        assembly {
            c := b

            if gt(b, a) {
                c := a
            }
        }
    }

    //solhint-disable
    /// @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    /// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv

    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // Handle division by zero
        require(denominator > 0);

        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remiander Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Short circuit 256 by 256 division
        // This saves gas when a * b is small, at the cost of making the
        // large case a bit more expensive. Depending on your use case you
        // may want to remove this short circuit and always go through the
        // 512 bit path.
        if (prod1 == 0) {
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Handle overflow, the result must be < 2**256
        require(prod1 < denominator);

        // Make division exact by subtracting the remainder from [prod1 prod0]
        // Compute remainder using mulmod
        // Note mulmod(_, _, 0) == 0
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        // Compute largest power of two divisor of denominator.
        // Always >= 1 unless denominator is zero, then twos is zero.
        uint256 twos = denominator & (~denominator + 1);
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need
        // to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256
        // Now that denominator is an odd number, it has an inverse
        // modulo 2**256 such that denominator * inv = 1 mod 2**256.
        // Compute the inverse by starting with a seed that is correct
        // correct for four bits. That is, denominator * inv = 1 mod 2**4
        // If denominator is zero the inverse starts with 2
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson itteration to improve the precision.
        // Thanks to Hensel's lifting lemma, this also works in modular
        // arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256
        // If denominator is zero, inv is now 128

        // Because the division is now exact we can divide by multiplying
        // with the modular inverse of denominator. This will give us the
        // correct result modulo 2**256. Since the precoditions guarantee
        // that the outcome is less than 2**256, this is the final result.
        // We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;
        return result;
    }

    /**
     * @notice This was copied from Uniswap without any modifications.
     * https://github.com/Uniswap/v2-core/blob/master/contracts/libraries/Math.sol
     * babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
     */
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
