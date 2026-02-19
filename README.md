# PWN Protocol

PWN is a protocol that enables peer-to-peer (P2P) loans using arbitrary collateral. Our smart contracts support ERC20, ERC721, and ERC1155 standards, making it versatile and adaptable to a wide range of use cases.

## About

In the world of decentralized finance, PWN stands out with its unique approach to P2P loans. By allowing users to leverage different types of collateral, we provide flexibility and convenience that's unmatched in the industry.

## Developer Documentation

For developers interested in integrating with or building on top of PWN, we provide comprehensive documentation. You can find in-depth information about our smart contracts and their usage in the [PWN Developer Docs](https://dev-docs.pwn.xyz/).

## Deployment

| Name                                   | Address                                    |
|----------------------------------------|--------------------------------------------|
| Config                                 | 0xd52a2898d61636bB3eEF0d145f05352FF543bdCC |
| Hub                                    | 0x37807A2F031b3B44081F4b21500E5D70EbaDAdd5 |
| LOAN Token                             | 0x4440C069272cC34b80C7B11bEE657D0349Ba9C23 |
| Revoked Nonce                          | 0x972204fF33348ee6889B2d0A3967dB67d7b08e4c |
| Utilized Credit                        | 0x8E6F44DEa3c11d69C63655BDEcbA25Fa986BCE9D |
| Simple Loan                            | 0x719A69d0dc67bd3Aa7648D4694081B3c87952797 |
| Simple Loan Simple Proposal            | 0xe624E7D33baC728bE2bdB606Da0018B6E05A84D9 |
| Simple Loan List Proposal              | 0x7160Ec33788Df9AFb8AAEe777e7Ae21151B51eDd |
| Simple Loan Elastic Chainlink Proposal | see [Elastic Chainlink Proposal table](#elastic-chainlink-proposal) |
| Simple Loan Elastic Proposal           | 0xeC6390D4B22FFfD22E5C5FDB56DaF653C3Cd0626 |
| Simple Loan Dutch Auction Proposal     | 0x1b1394F436cAeaE139131E9bca6f5d5A2A7e1369 |

The addresses listed in the table above are the same on all deployed chains. This means that regardless of the blockchain network you are using, such as Ethereum or Arbitrum, the addresses for the PWN smart contracts remain consistent. This provides a seamless experience for developers and users who want to interact with the PWN protocol across different blockchain ecosystems.

### Elastic Chainlink Proposal
Elastic Chainlink Proposal addresses differ across chains due to unique constructor parameters. Below are the addresses for the Elastic Chainlink Proposal on each supported chain:

| Chain                                  | Address                                    |
|----------------------------------------|--------------------------------------------|
| Ethereum                               | 0xBA58E16BE93dAdcBB74a194bDfD9E5933b24016B |
| Optimism                               | 0xC267A16836D475561b37e7166ABeB92d876C8A3c |
| Binance Smart Chain                    | 0x79E1D066131C93610475C9AAEe3De861A8Cd2B71 |
| Gnosis Chain                           | 0x1719591db6AD58643aD4804eF8C2f2E51768C30E |
| Unichain                               | --- not deployed ---                       |
| Polygon                                | 0x5A8164910e995781C154fb092653752cE6BCDCA7 |
| Sonic                                  | 0xc2bCAFB3bf06FCeb54ae1f3902d6EEe020a4478B |
| World Chain                            | --- not deployed ---                       |
| Base                                   | 0xB6E4B8Ba8E26ac8d4979a8227DAda26bD3Ac9A10 |
| Arbitrum                               | 0xc566994F7c9D65C58a8f0C16F91b00Da6aE32BB6 |
| Celo                                   | 0x53fb85416cAeEE7f4d142F88685e2094f6E9E985 |
| Linea                                  | 0x8E9955B34606f601491c14d5cc8247F5E0477ff1 |
| Ink                                    | --- not deployed ---                       |
| Sepolia                                | 0xC46170F43b97faE1A8B507d6fdDaFfBb7527D61B |

Please note that some chains are currently not supported by Chainlink. As a result, the Elastic Chainlink Proposal has not been deployed on these chains. We are closely monitoring the support status and will deploy the necessary contracts as soon as Chainlink becomes available on these networks.

### Deployed Chains

PWN is deployed on the following chains:

- Ethereum (1)
- Optimism (10)
- Binance Smart Chain (56)
- Gnosis Chain (100)
- Unichain (130)
- Polygon (137)
- Sonic (146)
- World Chain (480)
- Base (8453)
- Arbitrum (42161)
- Celo (42220)
- Ink (57073)
- Linea (59144)
- Sepolia (11155111)

## Contributing

We welcome contributions from the community. If you're a developer interested in contributing to PWN, please see our developer docs for more information.

## Contact

If you have any questions or suggestions, feel free to reach out to us. We're always happy to hear from our users.
