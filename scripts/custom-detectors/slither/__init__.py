from .inconsistent_state_tracking import InconsistentStateTracking
from .erc4626_inflation import ERC4626Inflation
from .uncollateralized_borrow import UncollateralizedBorrow
from .donation_attack import DonationAttack

def make_plugin():
    return ([InconsistentStateTracking, ERC4626Inflation, UncollateralizedBorrow, DonationAttack], [])
