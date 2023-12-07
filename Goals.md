
Security
Re-usability
Dev time
multicall


execute from:
- gnosis safe
- eoa
- contract

allowed token:
- protocol (router?)
- token address
- owner


1 router per customer?
1 router per basket of tokens?



-----


allow dynamic token list on a per customer basis
-> they enable their own token list on each router
mapping(`user address:token address` => true/false)


do routers need to know about each other? doesn't seem like it.


individual routers (with multicall) for each protocol.
one multicall router that uses them. this is like a meta router.

a router consists of:
- multicall
- an interface to interact with something else (e.g. uniswap)
- a token list

=> abstract contract Router is IMulticall, ReentrancyGuard, ITokenWhitelist

there must also be a universal router that routes all the routers

----


make token allow list a self contained contract?
- users can whitelist tokens for specific routers

universal router doesn't care about allow list. it just routes to the correct router.







