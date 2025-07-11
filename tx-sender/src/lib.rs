pub mod utils;
use alloy::{
    providers::{RootProvider, Identity, fillers::{JoinFill, FillProvider, GasFiller, BlobGasFiller, NonceFiller, ChainIdFiller}},
};
pub type MyProvider = FillProvider<JoinFill<Identity, JoinFill<GasFiller, JoinFill<BlobGasFiller, JoinFill<NonceFiller, ChainIdFiller>>>>, RootProvider>;