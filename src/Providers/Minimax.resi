// Minimax provider interface — cross-module surface.
let createMinimaxProvider: unit => Provider.quotaProvider
let parseMinimaxCli: string => array<Domain.quotaData>
type fetchStep =
  | UseSession(array<Domain.quotaData>)
  | LoginWithKey(string)
  | GiveUp
let decideFetchStep: (option<array<Domain.quotaData>>, option<string>) => fetchStep
